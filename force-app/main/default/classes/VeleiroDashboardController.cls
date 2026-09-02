/**
 * Dashboard de Veleiro (Home): overview de la entrega en la plataforma.
 * Trae clients + projects en vivo (callouts), los agrupa por client y calcula
 * KPIs + el completion rate (progress) de cada project.
 */
public with sharing class VeleiroDashboardController {

    // Base humana del portal de Veleiro (hipervinculos). Config: Veleiro_Config__c.App_Base_Url__c (default beta).
    private static String appBase() { return VeleiroApiClient.appBaseUrl(); }

    public class ProjectRow {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Integer progress;
        @AuraEnabled public String status;
        @AuraEnabled public String url;
    }

    public class ClientRow {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String url;
        @AuraEnabled public Integer projectCount;
        @AuraEnabled public Integer avgProgress;
        @AuraEnabled public List<ProjectRow> projects = new List<ProjectRow>();
    }

    public class Overview {
        @AuraEnabled public Integer clientCount = 0;
        @AuraEnabled public Integer projectCount = 0;
        @AuraEnabled public Integer openProjectCount = 0;
        @AuraEnabled public Integer completedProjectCount = 0;
        @AuraEnabled public Integer avgProgress = 0;
        @AuraEnabled public List<ClientRow> clients = new List<ClientRow>();
    }

    @AuraEnabled
    public static Overview getOverview() {
        Overview ov = new Overview();

        // 1) Clients
        Map<String, ClientRow> byId = new Map<String, ClientRow>();
        for (Object o : VeleiroApiClient.listAll('/clients', null)) {
            Map<String, Object> c = (Map<String, Object>) o;
            if (c.get('is_archived') == true) continue;
            ClientRow cr = new ClientRow();
            cr.id = (String) c.get('id');
            cr.name = (String) c.get('name');
            cr.url = appBase() + '/a/partner-portal/organizations/' + cr.id;
            byId.put(cr.id, cr);
        }

        // 2) Projects -> agrupar por client_id
        Integer totalProgress = 0;
        for (Object o : VeleiroApiClient.listAll('/projects', null)) {
            Map<String, Object> p = (Map<String, Object>) o;
            if (p.get('is_archived') == true) continue;

            ProjectRow pr = new ProjectRow();
            pr.id = (String) p.get('id');
            pr.name = (String) p.get('name');
            pr.status = (String) p.get('status');
            pr.progress = (p.get('progress') != null) ? Integer.valueOf(String.valueOf(p.get('progress'))) : 0;
            pr.url = appBase() + '/a/partner-portal/projects/' + pr.id;

            ov.projectCount++;
            totalProgress += pr.progress;
            if (pr.progress >= 100 || pr.status == 'completed') {
                ov.completedProjectCount++;
            } else {
                ov.openProjectCount++;
            }

            String cid = (String) p.get('client_id');
            ClientRow cr = byId.get(cid);
            if (cr == null) {
                // project sin client conocido (o client archivado): lo colgamos de un cubo "Unassigned"
                cr = byId.get('__unassigned__');
                if (cr == null) {
                    cr = new ClientRow();
                    cr.id = '__unassigned__';
                    cr.name = 'Unassigned';
                    byId.put(cr.id, cr);
                }
            }
            cr.projects.add(pr);
        }

        // 3) Rollups por client + orden
        List<ClientRow> rows = new List<ClientRow>();
        for (ClientRow cr : byId.values()) {
            cr.projectCount = cr.projects.size();
            Integer sum = 0;
            for (ProjectRow pr : cr.projects) sum += pr.progress;
            cr.avgProgress = (cr.projectCount > 0) ? (sum / cr.projectCount) : 0;
            rows.add(cr);
        }
        // Clients con proyectos primero, luego por nombre
        rows.sort(new ClientComparator());

        ov.clients = rows;
        ov.clientCount = byId.containsKey('__unassigned__') ? byId.size() - 1 : byId.size();
        ov.avgProgress = (ov.projectCount > 0) ? (totalProgress / ov.projectCount) : 0;
        return ov;
    }

    // Ordena: mas proyectos primero; empate -> nombre asc.
    private class ClientComparator implements Comparator<ClientRow> {
        public Integer compare(ClientRow a, ClientRow b) {
            if (a.projects.size() != b.projects.size()) {
                return b.projects.size() - a.projects.size();
            }
            String an = (a.name != null) ? a.name.toLowerCase() : '';
            String bn = (b.name != null) ? b.name.toLowerCase() : '';
            return an.compareTo(bn);
        }
    }
}
