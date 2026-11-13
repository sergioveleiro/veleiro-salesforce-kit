/**
 * Mock reutilizable de la API de Veleiro para los tests (HttpCalloutMock).
 * Enruta por recurso (/clients, /projects, /tasks, /tasks/states, /meetings) y metodo,
 * devolviendo cuerpos canned que cada test puede sobreescribir.
 *
 * Uso:
 *   VeleiroApiMock mock = new VeleiroApiMock();
 *   mock.clientsBody = '{"data":[...],"has_more":false}';
 *   Test.setMock(HttpCalloutMock.class, mock);
 */
@isTest
public class VeleiroApiMock implements HttpCalloutMock {

    // Cuerpos por recurso (listas). Default vacio.
    public String clientsBody  = '{"data":[],"has_more":false}';
    public String projectsBody = '{"data":[],"has_more":false}';
    public String tasksBody    = '{"data":[],"has_more":false}';
    public String meetingsBody = '{"data":[],"has_more":false}';
    public String transcriptBody = '{"data":{"id":"trn_1","meeting_id":"bot_new","source":"meeting_bot",'
        + '"text":"[00:00:01] Ana: Hola\\n[00:00:04] Luis: Arrancamos","participants":[{"name":"Ana","email":"ana@acme.com"},'
        + '{"name":"Luis","email":null}]}}';
    public String statesBody   = '{"data":[]}';

    // Cuerpos para escritura / single GET.
    public String postClientBody  = '{"data":{"id":"org_test","name":"Test Client","slug":"test-client","version":1}}';
    public String postProjectBody = '{"data":{"id":"prjct_test","name":"Test Project","progress":0,"status":"planning","version":1}}';
    public String singleClientBody  = '{"data":{"id":"org_test","name":"Test Client","version":1,"additional_fields":{}}}';
    public String singleProjectBody = '{"data":{"id":"prjct_test","name":"Test Project","progress":0,"status":"planning","version":1,"additional_fields":{}}}';

    // Forzar un error/estado para probar ramas (ej. 409 version_conflict, 429, 404).
    public Integer overrideStatus = null;
    public String  overrideBody   = null;
    // Para simular 409 solo la primera vez y luego exito (retry).
    public Boolean failOnceWith409 = false;
    private Boolean already409 = false;

    // Captura del ultimo body enviado (para aseverar el payload en los tests).
    public String lastPostBody;
    public String lastPatchBody;
    // Cuantos POST por recurso: para probar que un lote crea UN client y N projects.
    public Integer clientPosts = 0;
    public Integer projectPosts = 0;
    // Veleiro_Client_Id__c y Veleiro_Project_Id__c son unicos: un lote de verdad necesita un id
    // distinto por create (org_test_1, prjct_test_2, ...). Los GET/PATCH por id siguen respondiendo.
    public Boolean distinctIds = false;

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        String url = req.getEndpoint();
        String m = req.getMethod();

        if (m == 'POST') lastPostBody = req.getBody();
        else if (m == 'PATCH') lastPatchBody = req.getBody();

        if (failOnceWith409 && m == 'PATCH' && !already409) {
            already409 = true;
            res.setStatusCode(409);
            res.setBody('{"error":{"code":"version_conflict","detail":{"current_version":9}}}');
            return res;
        }
        if (overrideStatus != null) {
            res.setStatusCode(overrideStatus);
            res.setBody(overrideBody != null ? overrideBody : '{"error":{"code":"internal_error"}}');
            return res;
        }

        res.setStatusCode(200);
        if (url.contains('/tasks/states')) {
            res.setBody(statesBody);
        } else if (m == 'POST' && url.contains('/clients')) {
            clientPosts++;
            res.setStatusCode(201);
            res.setBody(distinctIds ? postClientBody.replace('"org_test"', '"org_test_' + clientPosts + '"') : postClientBody);
        } else if (m == 'POST' && url.contains('/projects')) {
            projectPosts++;
            res.setStatusCode(201);
            res.setBody(distinctIds ? postProjectBody.replace('"prjct_test"', '"prjct_test_' + projectPosts + '"') : postProjectBody);
        } else if (url.contains('/clients/org')) {          // GET/PATCH single client
            res.setBody(singleClientBody);
        } else if (url.contains('/projects/prjct')) {       // GET/PATCH single project
            res.setBody(singleProjectBody);
        } else if (url.contains('/transcript')) {
            res.setBody(transcriptBody);
        } else if (url.contains('/meetings')) {
            res.setBody(meetingsBody);
        } else if (url.contains('/clients')) {
            res.setBody(clientsBody);
        } else if (url.contains('/projects')) {
            res.setBody(projectsBody);
        } else if (url.contains('/tasks')) {
            res.setBody(tasksBody);
        } else {
            res.setBody('{"data":[]}');
        }
        return res;
    }

    // Helper: inserta el Veleiro_Config__c org-default para que las clases no truenen.
    public static void seedConfig() {
        VeleiroTestAccess.grant();
        insert new Veleiro_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Api_Token__c = 'test-token',
            Base_Url__c  = 'https://test.veleiro.local/api/v1',
            App_Base_Url__c = 'https://app.test.veleiro.local'
        );
    }
}
