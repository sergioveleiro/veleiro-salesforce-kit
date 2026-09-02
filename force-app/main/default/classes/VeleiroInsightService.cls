/**
 * Velly Insights — la "AI" de Veleiro (mascota Velly) que traduce datos de ENTREGA
 * en acciones de VENTA para el seller.
 *
 * El motor es determinista y corre sobre SENALES REALES que ya trae la API:
 *   - progress (% del project)         - status (planning/active/...)
 *   - updated_at -> dias sin movimiento (proxy de momentum/estancamiento)
 *   - tasks en state_type = 'blocked' (Input Required / Action Needed = bloqueo del cliente)
 *
 * Salidas: health score (0-100), etiqueta nautica, "motion" de venta
 * (Expand / Protect / Unblock / Onboard / Reference / Nurture),
 * narrativa de Velly y next-best-action.
 */
public with sharing class VeleiroInsightService {

    // Base humana del portal de Veleiro (hipervinculos). Config: Veleiro_Config__c.App_Base_Url__c (default beta).
    private static String appBase() { return VeleiroApiClient.appBaseUrl(); }

    public class ClientInsight {
        @AuraEnabled public String clientId;
        @AuraEnabled public String sfAccountId;
        @AuraEnabled public String name;
        @AuraEnabled public String url;
        @AuraEnabled public Integer score;
        @AuraEnabled public String healthLabel;
        @AuraEnabled public String emoji;
        @AuraEnabled public String motionKey;    // expand | protect | unblock | onboard | reference | nurture
        @AuraEnabled public String motionLabel;  // texto para el chip
        @AuraEnabled public String narrative;    // lo que "dice" Velly
        @AuraEnabled public String nextAction;   // 1 accion concreta para el seller
        @AuraEnabled public Integer avgProgress;
        @AuraEnabled public Integer daysStalled;
        @AuraEnabled public Integer blockedTasks;
        @AuraEnabled public Integer projectCount;
        @AuraEnabled public Boolean synced;
    }

    public class Briefing {
        @AuraEnabled public String headline;      // resumen en lenguaje natural de Velly
        @AuraEnabled public Integer clientCount = 0;
        @AuraEnabled public Integer expandCount = 0;
        @AuraEnabled public Integer riskCount = 0;
        @AuraEnabled public Integer attentionCount = 0;
        @AuraEnabled public List<ClientInsight> expand = new List<ClientInsight>();
        @AuraEnabled public List<ClientInsight> risk = new List<ClientInsight>();
        @AuraEnabled public List<ClientInsight> attention = new List<ClientInsight>();
    }

    // ---------- API para el dashboard ----------
    @AuraEnabled
    public static Briefing getBriefing() {
        List<ClientInsight> all = computeAll();
        Briefing b = new Briefing();
        b.clientCount = all.size();

        for (ClientInsight ci : all) {
            if (ci.motionKey == 'expand' || ci.motionKey == 'reference') {
                b.expand.add(ci);
            } else if (ci.motionKey == 'protect' || ci.motionKey == 'unblock') {
                b.risk.add(ci);
            } else {
                b.attention.add(ci);
            }
        }
        // ordenar: expand por score desc, risk por score asc (mas urgente primero)
        b.expand.sort(new ByScoreDesc());
        b.risk.sort(new ByScoreAsc());
        b.expandCount = b.expand.size();
        b.riskCount = b.risk.size();
        b.attentionCount = b.attention.size();
        b.headline = buildHeadline(b);
        return b;
    }

    // ---------- API para la Account record page ----------
    @AuraEnabled
    public static ClientInsight getInsightForAccount(Id accountId) {
        Account a = [SELECT Id, Name, Veleiro_Client_Id__c FROM Account WHERE Id = :accountId LIMIT 1];
        if (String.isBlank(a.Veleiro_Client_Id__c)) {
            ClientInsight none = new ClientInsight();
            none.synced = false;
            none.name = a.Name;
            return none;
        }
        for (ClientInsight ci : computeAll()) {
            if (ci.clientId == a.Veleiro_Client_Id__c) return ci;
        }
        ClientInsight fallback = new ClientInsight();
        fallback.synced = true;
        fallback.name = a.Name;
        fallback.clientId = a.Veleiro_Client_Id__c;
        fallback.narrative = 'Velly is still gathering delivery signals for this client.';
        return fallback;
    }

    // ================= Motor =================

    private static List<ClientInsight> computeAll() {
        // 1) mapa status_id -> state_type (para detectar 'blocked')
        Map<String, String> stateType = new Map<String, String>();
        try {
            Map<String, Object> st = VeleiroApiClient.doGet('/tasks/states', null);
            for (Object o : (List<Object>) st.get('data')) {
                Map<String, Object> s = (Map<String, Object>) o;
                stateType.put((String) s.get('id'), (String) s.get('state_type'));
            }
        } catch (Exception e) { /* si falla, seguimos sin la senal de bloqueo */ }

        // 2) tasks bloqueadas por client
        Map<String, Integer> blockedByClient = new Map<String, Integer>();
        try {
            for (Object o : VeleiroApiClient.listAll('/tasks', null)) {
                Map<String, Object> t = (Map<String, Object>) o;
                if (t.get('is_archived') == true) continue;
                String cid = (String) t.get('client_id');
                if (String.isBlank(cid)) continue;
                String type = stateType.get((String) t.get('status_id'));
                if (type == 'blocked') {
                    blockedByClient.put(cid, (blockedByClient.containsKey(cid) ? blockedByClient.get(cid) : 0) + 1);
                }
            }
        } catch (Exception e) { /* sin tasks, seguimos */ }

        // 3) clients
        Map<String, ClientInsight> byId = new Map<String, ClientInsight>();
        for (Object o : VeleiroApiClient.listAll('/clients', null)) {
            Map<String, Object> c = (Map<String, Object>) o;
            if (c.get('is_archived') == true) continue;
            ClientInsight ci = new ClientInsight();
            ci.clientId = (String) c.get('id');
            ci.name = (String) c.get('name');
            ci.url = appBase() + '/a/partner-portal/organizations/' + ci.clientId;
            ci.synced = true;
            ci.projectCount = 0;
            ci.blockedTasks = blockedByClient.containsKey(ci.clientId) ? blockedByClient.get(ci.clientId) : 0;
            Object af = c.get('additional_fields');
            if (af instanceof Map<String, Object>) {
                Object sfid = ((Map<String, Object>) af).get('sf_account_id');
                if (sfid != null) ci.sfAccountId = String.valueOf(sfid);
            }
            byId.put(ci.clientId, ci);
        }

        // 4) projects -> agregados por client
        Map<String, Integer> sumProgress = new Map<String, Integer>();
        Map<String, Integer> maxStalled = new Map<String, Integer>();
        for (Object o : VeleiroApiClient.listAll('/projects', null)) {
            Map<String, Object> p = (Map<String, Object>) o;
            if (p.get('is_archived') == true) continue;
            String cid = (String) p.get('client_id');
            ClientInsight ci = byId.get(cid);
            if (ci == null) continue;
            Integer prog = (p.get('progress') != null) ? Integer.valueOf(String.valueOf(p.get('progress'))) : 0;
            Integer stalled = daysSince((String) p.get('updated_at'));
            ci.projectCount++;
            sumProgress.put(cid, (sumProgress.containsKey(cid) ? sumProgress.get(cid) : 0) + prog);
            Integer curMax = maxStalled.containsKey(cid) ? maxStalled.get(cid) : 0;
            if (stalled > curMax) maxStalled.put(cid, stalled);
        }

        // 5) reglas -> insight
        List<ClientInsight> out = new List<ClientInsight>();
        for (ClientInsight ci : byId.values()) {
            ci.avgProgress = (ci.projectCount > 0) ? (sumProgress.get(ci.clientId) / ci.projectCount) : 0;
            ci.daysStalled = maxStalled.containsKey(ci.clientId) ? maxStalled.get(ci.clientId) : 0;
            score(ci);
            out.add(ci);
        }
        return out;
    }

    // Reglas de Velly (prioridad de arriba hacia abajo).
    private static void score(ClientInsight ci) {
        Integer prog = ci.avgProgress;
        Integer stalled = ci.daysStalled;
        Integer blocked = ci.blockedTasks;

        if (blocked >= 1) {
            ci.emoji = '🟠'; // 🟠
            ci.healthLabel = 'Choppy waters';
            ci.motionKey = 'unblock';
            ci.motionLabel = 'Unblock';
            ci.score = clamp(45 - 10 * blocked + prog / 4);
            ci.narrative = blocked + ' task' + (blocked > 1 ? 's are' : ' is') +
                ' waiting on ' + ci.name + '. Delivery is blocked on the client’s side.';
            ci.nextAction = 'Nudge ' + ci.name + ' to clear the blocked item — a quick call keeps the renewal on course.';
            return;
        }
        if (prog == 0 && stalled >= 14) {
            ci.emoji = '🔴'; // 🔴
            ci.healthLabel = 'Off course';
            ci.motionKey = 'protect';
            ci.motionLabel = 'Protect renewal';
            ci.score = clamp(28 - stalled / 3);
            ci.narrative = 'No delivery movement in ' + stalled + ' days and still at 0%. This account is drifting.';
            ci.nextAction = 'Re-engage ' + ci.name + ' before the renewal window — stalled onboarding is the #1 churn signal.';
            return;
        }
        if (prog == 0 && stalled <= 7) {
            ci.emoji = '🟡'; // 🟡
            ci.healthLabel = 'Just set sail';
            ci.motionKey = 'onboard';
            ci.motionLabel = 'Onboarding';
            ci.score = 60;
            ci.narrative = 'Kickoff just landed for ' + ci.name + '. First tasks are being scoped.';
            ci.nextAction = 'Introduce the delivery team and lock the first milestone date with ' + ci.name + '.';
            return;
        }
        if (stalled > 21) {
            ci.emoji = '🔴'; // 🔴
            ci.healthLabel = 'Off course';
            ci.motionKey = 'protect';
            ci.motionLabel = 'Protect renewal';
            ci.score = clamp(35 - stalled / 4 + prog / 4);
            ci.narrative = ci.name + ' has stalled for ' + stalled + ' days at ' + prog + '%. Momentum has stopped.';
            ci.nextAction = 'Book a check-in with ' + ci.name + ' to restart delivery before it hurts the renewal.';
            return;
        }
        if (prog >= 95) {
            ci.emoji = '🟢'; // 🟢
            ci.healthLabel = 'Smooth sailing';
            ci.motionKey = 'reference';
            ci.motionLabel = 'Ask for reference';
            ci.score = clamp(prog);
            ci.narrative = 'Delivery for ' + ci.name + ' is essentially complete and healthy.';
            ci.nextAction = 'Ask ' + ci.name + ' for a reference or case study — delivery-happy customers convert to advocates.';
            return;
        }
        if (prog >= 30) {
            ci.emoji = '🟢'; // 🟢
            ci.healthLabel = 'Smooth sailing';
            ci.motionKey = 'expand';
            ci.motionLabel = 'Expansion play';
            ci.score = clamp(prog + 15);
            ci.narrative = ci.name + ' is ' + prog + '% delivered and moving (updated ' + stalled + 'd ago). ' +
                'Clients this healthy tend to expand within ~60 days.';
            ci.nextAction = 'Line up an expansion conversation with ' + ci.name + ' while delivery goodwill is high.';
            return;
        }
        // en progreso pero temprano
        ci.emoji = '🟡'; // 🟡
        ci.healthLabel = 'Steady';
        ci.motionKey = 'nurture';
        ci.motionLabel = 'Nurture';
        ci.score = clamp(prog + 25);
        ci.narrative = ci.name + ' is ' + prog + '% delivered, last update ' + stalled + 'd ago. On a healthy course.';
        ci.nextAction = 'Keep momentum with ' + ci.name + ' and watch for an expansion opening as they near go-live.';
    }

    private static String buildHeadline(Briefing b) {
        if (b.clientCount == 0) return 'No clients in Veleiro yet — once you sync one, Velly will chart the course. 🧭';
        List<String> parts = new List<String>();
        parts.add('You have ' + b.clientCount + ' client' + (b.clientCount == 1 ? '' : 's') + ' in Veleiro.');
        if (!b.risk.isEmpty()) {
            ClientInsight r = b.risk[0];
            String reason = r.narrative.split('\\. ')[0]; // primera frase, sin cortar mayusculas
            parts.add(r.emoji + ' ' + r.name + ' needs rescuing — ' + reason + '.');
        }
        if (!b.expand.isEmpty()) {
            ClientInsight e = b.expand[0];
            parts.add(e.emoji + ' ' + e.name + ' is your best expansion play right now.');
        }
        // "esta semana"
        List<String> focus = new List<String>();
        if (!b.risk.isEmpty()) focus.add('rescue ' + b.risk[0].name);
        if (!b.expand.isEmpty()) focus.add('expand ' + b.expand[0].name);
        if (!focus.isEmpty()) parts.add('This week: ' + String.join(focus, ', ') + '.');
        return String.join(parts, ' ');
    }

    // dias desde una fecha ISO (yyyy-MM-ddTHH:mm:ss...). Robusto a formato con zona.
    private static Integer daysSince(String iso) {
        if (String.isBlank(iso) || iso.length() < 10) return 0;
        try {
            String d = iso.substring(0, 10);
            List<String> p = d.split('-');
            Date dt = Date.newInstance(Integer.valueOf(p[0]), Integer.valueOf(p[1]), Integer.valueOf(p[2]));
            Integer diff = dt.daysBetween(Date.today());
            return (diff < 0) ? 0 : diff;
        } catch (Exception e) {
            return 0;
        }
    }

    private static Integer clamp(Integer v) {
        if (v < 0) return 0;
        if (v > 100) return 100;
        return v;
    }

    public class ByScoreDesc implements Comparator<ClientInsight> {
        public Integer compare(ClientInsight a, ClientInsight b) { return b.score - a.score; }
    }
    public class ByScoreAsc implements Comparator<ClientInsight> {
        public Integer compare(ClientInsight a, ClientInsight b) { return a.score - b.score; }
    }
}
