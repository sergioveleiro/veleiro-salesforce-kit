/**
 * Reuniones de Veleiro para un registro de Salesforce. Solo lectura: la API no tiene escritura
 * de meetings y el scope `meeting` ni siquiera acepta 'write'.
 *
 * Tres cosas que decidieron la forma de esta clase:
 *
 *  1. Cada fila trae su propio `url` al portal de Veleiro. Se muestra TAL CUAL. Armarla aqui
 *     (app base + /a/partner-portal/meetings/<id>/) funcionaria hoy y se romperia el dia que
 *     ellos cambien la ruta, sin que nadie se entere hasta que un cliente haga clic.
 *  2. Una reunion cuelga SIEMPRE de un client y SOLO A VECES de un project (`project_id` es
 *     nullable). El panel de Account ve mas que el de Opportunity: por eso hay dos entradas.
 *  3. El scope `meeting` es nuevo (API de octubre de 2026) y las keys nacen sin el, asi que una
 *     org que no lo haya habilitado recibe 403 insufficient_scope. Eso no es una falla que deba
 *     ensuciar el panel: es "todavia no esta encendido" -> scopeMissing, y el componente lo dice
 *     en una linea o se calla. Se ramifica por `code`, nunca por el mensaje.
 */
public with sharing class VeleiroMeetingService {

    // La API pagina por updated_at descendente, NO por la fecha de la reunion. Se pide una
    // pagina y se ordena aqui por start_time. Con mas reuniones tocadas que esto, una antigua
    // puede quedar fuera del panel; esta entera en Veleiro, a un clic de distancia.
    @TestVisible private static Integer fetchSize = 25;

    // El panel muestra un ASOMO del transcript, no el transcript. Una reunion de una hora son
    // decenas de miles de caracteres: volcarlos en una columna lateral no se lee, pesa, y le
    // quita la razon de abrir Veleiro, que es donde esta la conversacion entera y lo que Veleiro
    // hace con ella. Se corta corto a proposito y el "seguir leyendo" se va para alla.
    @TestVisible private static Integer maxTranscriptChars = 700;

    public class Meeting implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String url;
        @AuraEnabled public String status;
        @AuraEnabled public String clientId;
        @AuraEnabled public String projectId;
        // Solo se resuelve del lado de la Account, que es donde conviven varios projects.
        @AuraEnabled public String projectName;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public Boolean hasTranscript;

        // Mas reciente primero; las que no tienen fecha, al final.
        public Integer compareTo(Object other) {
            Datetime mine = this.startTime;
            Datetime theirs = ((Meeting) other).startTime;
            if (mine == theirs) return 0;
            if (mine == null) return 1;
            if (theirs == null) return -1;
            return (mine > theirs) ? -1 : 1;
        }
    }

    public class Participant {
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    public class Transcript {
        @AuraEnabled public String meetingId;
        // meeting_bot (lo grabo el bot) | upload (lo subio una persona) | notes (se grabo en la app).
        @AuraEnabled public String source;
        @AuraEnabled public String text;
        @AuraEnabled public List<Participant> participants = new List<Participant>();
        // El texto venia mas largo que maxTranscriptChars y se corto.
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public Boolean scopeMissing = false;
        @AuraEnabled public Boolean reachable = true;
    }

    public class MeetingList {
        @AuraEnabled public List<Meeting> meetings = new List<Meeting>();
        // Los projects presentes en estas reuniones, para acotar la lista desde el UI.
        @AuraEnabled public List<VeleiroPulseService.ProjectRef> projects = new List<VeleiroPulseService.ProjectRef>();
        // La key de la org no tiene el scope `meeting`: hay que habilitarlo en el portal.
        @AuraEnabled public Boolean scopeMissing = false;
        // Falso cuando Veleiro no contesto o contesto con otro error: la seccion se oculta.
        @AuraEnabled public Boolean reachable = true;
        // Cuantas trajo la pagina antes de recortar, para que el UI diga "y N mas".
        @AuraEnabled public Integer total = 0;
    }

    /** Reuniones asignadas al project de esta Opportunity. Sin project vinculado no hay callout. */
    @AuraEnabled
    public static MeetingList getForOpportunity(Id opportunityId) {
        if (opportunityId == null) return new MeetingList();
        String projectId = null;
        for (Opportunity o : [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1]) {
            projectId = o.Veleiro_Project_Id__c;
        }
        return fetch('project_id', projectId);
    }

    /** Todas las del client de esta Account, tengan project o no. */
    @AuraEnabled
    public static MeetingList getForAccount(Id accountId) {
        if (accountId == null) return new MeetingList();
        String clientId = null;
        for (Account a : [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :accountId LIMIT 1]) {
            clientId = a.Veleiro_Client_Id__c;
        }
        MeetingList out = fetch('client_id', clientId);
        nameTheProjects(out, clientId);
        return out;
    }

    /**
     * Una Account puede tener varios projects, asi que sus reuniones se pueden acotar por uno.
     * El id no le dice nada a nadie: se resuelven los nombres con una llamada mas, y solo si
     * alguna reunion trae project. Si esa llamada falla, la lista sigue viva sin el filtro.
     */
    private static void nameTheProjects(MeetingList out, String clientId) {
        Set<String> present = new Set<String>();
        for (Meeting m : out.meetings) if (String.isNotBlank(m.projectId)) present.add(m.projectId);
        if (present.isEmpty()) return;
        try {
            Map<String, String> nameById = new Map<String, String>();
            for (VeleiroPulseService.ProjectRef ref : VeleiroPulseService.projectsOf(clientId)) {
                nameById.put(ref.id, ref.name);
            }
            for (Meeting m : out.meetings) {
                if (String.isNotBlank(m.projectId)) m.projectName = nameById.get(m.projectId);
            }
            for (String id : present) {
                VeleiroPulseService.ProjectRef ref = new VeleiroPulseService.ProjectRef();
                ref.id = id;
                ref.name = nameById.containsKey(id) ? nameById.get(id) : id;
                out.projects.add(ref);
            }
        } catch (Exception e) {
            out.projects.clear();   // sin nombres no hay filtro, pero las reuniones siguen ahi
        }
    }

    private static MeetingList fetch(String filterKey, String filterValue) {
        MeetingList out = new MeetingList();
        if (String.isBlank(filterValue)) return out;   // sin vinculo no hay nada que pedir
        try {
            Map<String, Object> body = VeleiroApiClient.doGet('/meetings', new Map<String, String>{
                filterKey => filterValue,
                'limit'   => String.valueOf(fetchSize)
            });
            Object data = body.get('data');
            if (!(data instanceof List<Object>)) return out;

            List<Meeting> all = new List<Meeting>();
            for (Object row : (List<Object>) data) {
                Meeting m = toMeeting((Map<String, Object>) row);
                if (m != null) all.add(m);
            }
            all.sort();                 // mas reciente primero; el UI puede darle la vuelta
            out.meetings = all;
            out.total = all.size();
        } catch (VeleiroApiClient.VeleiroApiException e) {
            if (e.code == 'insufficient_scope') {
                out.scopeMissing = true;        // falta encender el scope, no es una falla
            } else {
                out.reachable = false;          // la seccion es secundaria: se oculta y ya
            }
        } catch (Exception e) {
            out.reachable = false;
        }
        return out;
    }

    private static Meeting toMeeting(Map<String, Object> row) {
        if (row == null || String.isBlank((String) row.get('url'))) return null; // sin link no aporta
        Meeting m = new Meeting();
        m.id = (String) row.get('id');
        m.title = (String) row.get('title');
        m.url = (String) row.get('url');
        m.status = (String) row.get('status');
        m.clientId = (String) row.get('client_id');
        m.projectId = (String) row.get('project_id');
        m.startTime = parseIso((String) row.get('start_time'));
        m.endTime = parseIso((String) row.get('end_time'));
        m.hasTranscript = 'available'.equals((String) row.get('transcript_status'));
        return m;
    }

    /**
     * El texto de una reunion. Se pide SOLO cuando alguien abre esa fila: el endpoint tiene su
     * propio limite de rate, aparte del general, y traer todos los transcripts de la lista por
     * si acaso seria gastarselo para nada.
     */
    @AuraEnabled
    public static Transcript getTranscript(String meetingId) {
        Transcript t = new Transcript();
        t.meetingId = meetingId;
        if (String.isBlank(meetingId)) return t;
        try {
            Map<String, Object> body = VeleiroApiClient.doGet('/meetings/' + meetingId.trim() + '/transcript', null);
            Map<String, Object> data = (Map<String, Object>) body.get('data');
            if (data == null) return t;
            t.source = (String) data.get('source');
            String text = (String) data.get('text');
            if (text == null) text = '';
            if (text.length() > maxTranscriptChars) {
                text = text.abbreviate(maxTranscriptChars);
                t.truncated = true;
            }
            t.text = text;
            Object people = data.get('participants');
            if (people instanceof List<Object>) {
                for (Object o : (List<Object>) people) {
                    Map<String, Object> pm = (Map<String, Object>) o;
                    Participant p = new Participant();
                    p.name = (String) pm.get('name');
                    p.email = (String) pm.get('email');
                    t.participants.add(p);
                }
            }
        } catch (VeleiroApiClient.VeleiroApiException e) {
            if (e.code == 'insufficient_scope') { t.scopeMissing = true; } else { t.reachable = false; }
        } catch (Exception e) {
            t.reachable = false;
        }
        return t;
    }

    // Las fechas llegan en ISO 8601. Una que no se pueda leer deja la reunion sin fecha, nunca
    // tumba el panel entero.
    @TestVisible
    private static Datetime parseIso(String raw) {
        if (String.isBlank(raw)) return null;
        try {
            return (Datetime) JSON.deserialize('"' + raw + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }
}
