/**
 * El pulso de la entrega para un registro de Salesforce: tiempo invertido, trabajo abierto y
 * trabajo trabado. Es lo que un vendedor no puede ver en su CRM y decide una renovacion.
 *
 * Solo lectura, y cada numero sale de /tasks:
 *  - tiempo  -> suma de `logged_minutes` (lo que el equipo registro, de todos los miembros)
 *  - abierto -> tasks cuyo estado NO es 'done'
 *  - trabado -> tasks en estado 'blocked' (del lado del cliente, normalmente)
 *
 * `logged_minutes` NO mueve `updated_at` ni `version` de la task (lo dice la propia API), asi que
 * no hay forma de traer "solo lo nuevo": el total se recalcula leyendo las tasks del project.
 *
 * Costo en callouts: 1 (catalogo de estados) + 1 por project. Una Opportunity es 1 project, o sea
 * 2 llamadas. Una Account suma sus projects y se corta en maxProjectsPerClient para no vaciar el
 * limite de callouts que comparte con los procesos del cliente; cuando corta, lo dice (`partial`).
 */
public with sharing class VeleiroPulseService {

    // Hasta cuantos projects de un mismo client se suman. Los mas recientemente tocados primero,
    // que es el orden en que la API los devuelve.
    @TestVisible private static Integer maxProjectsPerClient = 10;

    public class ProjectRef {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    public class Pulse {
        @AuraEnabled public Integer loggedMinutes = 0;
        @AuraEnabled public Integer openTasks = 0;
        @AuraEnabled public Integer blockedTasks = 0;
        @AuraEnabled public Integer totalTasks = 0;
        // Los projects que se sumaron. En una Account tambien alimentan el filtro de reuniones.
        @AuraEnabled public List<ProjectRef> projects = new List<ProjectRef>();
        // El client tenia mas projects de los que se sumaron.
        @AuraEnabled public Boolean partial = false;
        @AuraEnabled public Boolean scopeMissing = false;
        @AuraEnabled public Boolean reachable = true;
        // Hay algo que valga la pena pintar.
        @AuraEnabled public Boolean hasData = false;
    }

    /** Pulso del project de esta Opportunity. */
    @AuraEnabled
    public static Pulse getForOpportunity(Id opportunityId) {
        Pulse p = new Pulse();
        if (opportunityId == null) return p;
        String projectId = null;
        for (Opportunity o : [SELECT Veleiro_Project_Id__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1]) {
            projectId = o.Veleiro_Project_Id__c;
        }
        if (String.isBlank(projectId)) return p;
        try {
            Map<String, String> stateById = stateTypes();
            ProjectRef ref = new ProjectRef();
            ref.id = projectId;
            p.projects.add(ref);
            addTasksOf(p, projectId, stateById);
            // Hay project vinculado: se muestra el pulso de ESE project aunque vaya en ceros.
            // Un project recien creado sin horas todavia es informacion: dice que arranco.
            p.hasData = true;
        } catch (VeleiroApiClient.VeleiroApiException e) {
            flag(p, e);
        } catch (Exception e) {
            p.reachable = false;
        }
        return p;
    }

    /** Pulso del client de esta Account: la suma de sus projects. */
    @AuraEnabled
    public static Pulse getForAccount(Id accountId) {
        Pulse p = new Pulse();
        if (accountId == null) return p;
        String clientId = null;
        for (Account a : [SELECT Veleiro_Client_Id__c FROM Account WHERE Id = :accountId LIMIT 1]) {
            clientId = a.Veleiro_Client_Id__c;
        }
        if (String.isBlank(clientId)) return p;
        try {
            List<ProjectRef> refs = projectsOf(clientId);
            p.partial = refs.size() > maxProjectsPerClient;
            Map<String, String> stateById = stateTypes();
            for (ProjectRef ref : refs) {
                if (p.projects.size() >= maxProjectsPerClient) break;
                p.projects.add(ref);
                addTasksOf(p, ref.id, stateById);
            }
            p.hasData = p.totalTasks > 0 || !p.projects.isEmpty();
        } catch (VeleiroApiClient.VeleiroApiException e) {
            flag(p, e);
        } catch (Exception e) {
            p.reachable = false;
        }
        return p;
    }

    /** Los projects de un client, para el pulso y para el filtro de reuniones. */
    public static List<ProjectRef> projectsOf(String clientId) {
        List<ProjectRef> out = new List<ProjectRef>();
        if (String.isBlank(clientId)) return out;
        for (Object o : VeleiroApiClient.listAll('/projects', new Map<String, String>{ 'client_id' => clientId })) {
            Map<String, Object> row = (Map<String, Object>) o;
            if (row.get('is_archived') == true) continue;
            ProjectRef ref = new ProjectRef();
            ref.id = (String) row.get('id');
            ref.name = (String) row.get('name');
            if (String.isNotBlank(ref.id)) out.add(ref);
        }
        return out;
    }

    // status_id -> state_type (initial | in_progress | blocked | review | done). Un catalogo chico.
    private static Map<String, String> stateTypes() {
        Map<String, String> byId = new Map<String, String>();
        Map<String, Object> body = VeleiroApiClient.doGet('/tasks/states', null);
        Object data = body.get('data');
        if (data instanceof List<Object>) {
            for (Object o : (List<Object>) data) {
                Map<String, Object> s = (Map<String, Object>) o;
                byId.put((String) s.get('id'), (String) s.get('state_type'));
            }
        }
        return byId;
    }

    private static void addTasksOf(Pulse p, String projectId, Map<String, String> stateById) {
        for (Object o : VeleiroApiClient.listAll('/tasks', new Map<String, String>{ 'project_id' => projectId })) {
            Map<String, Object> t = (Map<String, Object>) o;
            if (t.get('is_archived') == true) continue;
            p.totalTasks++;
            Object minutes = t.get('logged_minutes');
            if (minutes != null) p.loggedMinutes += Integer.valueOf(String.valueOf(minutes));
            String type = stateById.get((String) t.get('status_id'));
            if (type == 'blocked') p.blockedTasks++;
            if (type != 'done') p.openTasks++;   // un estado desconocido cuenta como trabajo vivo
        }
    }

    // Se ramifica por el code, nunca por el mensaje.
    private static void flag(Pulse p, VeleiroApiClient.VeleiroApiException e) {
        if (e.code == 'insufficient_scope') { p.scopeMissing = true; } else { p.reachable = false; }
    }
}
