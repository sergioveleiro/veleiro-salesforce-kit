/**
 * HTTP client for the Veleiro API (https://app.veleiro.ai/api/v1 by default).
 * Server-to-server from Apex only. Contract:
 *  - paths have NO trailing slash (a 301 drops the body),
 *  - envelope {"data": ...} with has_more / next_cursor,
 *  - cursor pagination (no offset),
 *  - errors branch on error.code, never on message,
 *  - 429 honors Retry-After,
 *  - writes send If-Match; a 409 version_conflict carries detail.current_version.
 *
 * The bearer token is sent only to a packaged Named Credential. A Base_Url__c value
 * that is not one of those credentials is ignored, so it cannot receive the token.
 */
public with sharing class VeleiroApiClient {

    public class VeleiroApiException extends Exception {
        public String code;
        public Integer currentVersion; // set on 409 version_conflict
    }

    public static final String CRED_PROD = 'Veleiro_API';
    public static final String CRED_BETA = 'Veleiro_API_Beta';
    public static final String CRED_PROD_SECURE = 'Veleiro_API_Secure';
    public static final String CRED_BETA_SECURE = 'Veleiro_API_Beta_Secure';
    private static final String DEFAULT_APP_BASE = 'https://app.veleiro.ai';

    /**
     * Callout path for one of our Named Credentials.
     * Inside the managed package the credential is veleiro__Veleiro_API. A bare
     * callout:Veleiro_API fails with "the named credential might not exist".
     * The prefix is empty on a source deploy, so the same code serves both branches.
     */
    public static String calloutTo(String credential) {
        return 'callout:' + VeleiroSyncConfig.namespacePrefix() + credential;
    }

    public static String defaultBase() { return calloutTo(CRED_PROD) + '/api/v1'; }

    private static Veleiro_Config__c cfg() {
        if (!VeleiroCredentialStore.hasToken()) {
            throw new VeleiroApiException(VeleiroI18n.t('err.tokenMissing'));
        }
        return resolveConfig();
    }

    // Org, profile, or user level. The token itself is not selected here.
    private static Veleiro_Config__c resolveConfig() {
        Veleiro_Config__c c = Veleiro_Config__c.getInstance();
        if (c != null && (String.isNotBlank(c.Base_Url__c) || String.isNotBlank(c.App_Base_Url__c))) return c;
        Veleiro_Config__c org = Veleiro_Config__c.getOrgDefaults();
        if (org != null && (String.isNotBlank(org.Base_Url__c) || String.isNotBlank(org.App_Base_Url__c))) return org;
        for (Veleiro_Config__c row : [
            SELECT Base_Url__c, App_Base_Url__c
            FROM Veleiro_Config__c
            WHERE Base_Url__c != null OR App_Base_Url__c != null
            LIMIT 1
        ]) {
            return row;
        }
        return org != null ? org : c;
    }

    public static Boolean hasToken() {
        return VeleiroCredentialStore.hasToken();
    }

    /**
     * Production vs beta, read from the saved setting, then mapped onto a packaged
     * Named Credential. Raw https URLs and unknown callout targets are not used.
     */
    @TestVisible
    private static String calloutBase(Veleiro_Config__c c, Boolean platform) {
        String cred = isBeta(c)
            ? (platform == true ? CRED_BETA_SECURE : CRED_BETA)
            : (platform == true ? CRED_PROD_SECURE : CRED_PROD);
        return calloutTo(cred) + '/api/v1';
    }

    private static Boolean isBeta(Veleiro_Config__c c) {
        String stored = '';
        if (c != null && c.Base_Url__c != null) stored += ' ' + c.Base_Url__c.toLowerCase();
        if (c != null && c.App_Base_Url__c != null) stored += ' ' + c.App_Base_Url__c.toLowerCase();
        return stored.contains('veleiro_api_beta') || stored.contains('app.beta.veleiro.dev');
    }

    /** Heals a stored callout:Veleiro_API that predates the namespace prefix. */
    @TestVisible
    private static String withNamespace(String url) {
        String prefix = VeleiroSyncConfig.namespacePrefix();
        if (String.isBlank(prefix) || String.isBlank(url) || !url.startsWith('callout:')) return url;
        String credential = url.substring('callout:'.length());
        if (credential.startsWithIgnoreCase(prefix)) return url;
        return 'callout:' + prefix + credential;
    }

    public static String appBaseUrl() {
        Veleiro_Config__c c = resolveConfig();
        String allowed = allowedAppBase(c == null ? null : c.App_Base_Url__c);
        if (allowed != null) return allowed;
        return isBeta(c) ? 'https://app.beta.veleiro.dev' : DEFAULT_APP_BASE;
    }

    private static String allowedAppBase(String url) {
        if (String.isBlank(url)) return null;
        String u = url.trim().toLowerCase();
        if (matchesHost(u, 'https://app.beta.veleiro.dev')) return 'https://app.beta.veleiro.dev';
        if (matchesHost(u, 'https://app.veleiro.ai')) return 'https://app.veleiro.ai';
        return null;
    }

    private static Boolean matchesHost(String url, String host) {
        if (!url.startsWith(host)) return false;
        String rest = url.substring(host.length());
        return rest == '' || rest.startsWith('/');
    }

    /** The callout base actually used (a callout: string, not a secret). */
    public static String apiBaseConfigured() {
        return calloutBase(resolveConfig(), VeleiroCredentialStore.platformAuthReady());
    }

    /** Confirms the secure Named Credential can read /clients before we depend on it. */
    public static void probeSecureCredential() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(calloutBase(resolveConfig(), true) + '/clients?limit=1');
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        handle(new Http().send(req));
    }

    private static HttpRequest baseReq(String method, String path) {
        Boolean platform = VeleiroCredentialStore.platformAuthReady();
        assertSafePath(path);
        Veleiro_Config__c c = cfg();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(calloutBase(c, platform) + path);
        req.setMethod(method);
        // The secure Named Credential injects Authorization. The legacy credential cannot.
        if (!platform) {
            // Legacy Named Credentials cannot send this header. Used only until the secure credential probe succeeds.
            req.setHeader('Authorization', 'Bearer ' + VeleiroCredentialStore.readToken());
        }
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        return req;
    }

    private static void assertSafePath(String path) {
        if (String.isBlank(path) || !path.startsWith('/')) {
            throw new VeleiroApiException(VeleiroI18n.t('err.requestRejected'));
        }
        String pathOnly = path;
        String query = '';
        Integer q = path.indexOf('?');
        if (q >= 0) {
            pathOnly = path.substring(0, q);
            query = path.substring(q + 1);
        }
        if (pathOnly.contains('..') || !Pattern.matches('/[A-Za-z0-9_./-]+', pathOnly)) {
            throw new VeleiroApiException(VeleiroI18n.t('err.requestRejected'));
        }
        if (String.isNotBlank(query) && !Pattern.matches('[A-Za-z0-9_=&%+.,-]*', query)) {
            throw new VeleiroApiException(VeleiroI18n.t('err.requestRejected'));
        }
    }

    private static Map<String, Object> handle(HttpResponse res) {
        Integer status = res.getStatusCode();
        Map<String, Object> body;
        try {
            body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            VeleiroApiException ex = new VeleiroApiException(
                VeleiroI18n.t('api.nonJson', new List<Object>{ status }));
            ex.code = 'internal_error';
            throw ex;
        }
        if (status >= 200 && status < 300) return body;

        VeleiroApiException ex = new VeleiroApiException();
        ex.code = 'internal_error';
        Object errObj = (body == null) ? null : body.get('error');
        if (errObj instanceof Map<String, Object>) {
            Map<String, Object> err = (Map<String, Object>) errObj;
            if (err.get('code') != null) ex.code = (String) err.get('code');
            Object det = err.get('detail');
            if (det instanceof Map<String, Object> && ((Map<String, Object>) det).get('current_version') != null) {
                ex.currentVersion = Integer.valueOf(String.valueOf(((Map<String, Object>) det).get('current_version')));
            }
        }
        if (status == 429) ex.code = 'rate_limited';
        ex.setMessage(messageFor(ex.code));
        throw ex;
    }

    private static String messageFor(String code) {
        if (code == 'invalid_token') return VeleiroI18n.t('api.invalid_token');
        if (code == 'insufficient_scope') return VeleiroI18n.t('api.insufficient_scope');
        if (code == 'not_found') return VeleiroI18n.t('api.not_found');
        if (code == 'validation_failed') return VeleiroI18n.t('api.validation_failed');
        if (code == 'version_conflict') return VeleiroI18n.t('api.version_conflict');
        if (code == 'invalid_cursor') return VeleiroI18n.t('api.invalid_cursor');
        if (code == 'rate_limited') return VeleiroI18n.t('api.rate_limited');
        if (code == 'method_not_allowed') return VeleiroI18n.t('api.method_not_allowed');
        return VeleiroI18n.t('api.internal_error');
    }

    public static Map<String, Object> doGet(String path, Map<String, String> query) {
        String qs = '';
        if (query != null && !query.isEmpty()) {
            List<String> parts = new List<String>();
            for (String k : query.keySet()) {
                parts.add(EncodingUtil.urlEncode(k, 'UTF-8') + '=' + EncodingUtil.urlEncode(query.get(k), 'UTF-8'));
            }
            qs = '?' + String.join(parts, '&');
        }
        HttpRequest req = baseReq('GET', path + qs);
        return handle(new Http().send(req));
    }

    public static List<Object> listAll(String path, Map<String, String> filters) {
        List<Object> all = new List<Object>();
        Map<String, String> q = (filters != null) ? filters.clone() : new Map<String, String>();
        q.put('limit', '100');
        Integer guard = 0;
        while (true) {
            Map<String, Object> body = doGet(path, q);
            Object data = body.get('data');
            if (data instanceof List<Object>) all.addAll((List<Object>) data);
            Boolean hasMore = (body.get('has_more') == true);
            String next = (String) body.get('next_cursor');
            if (!hasMore || String.isBlank(next) || guard++ >= 100) break;
            q.put('cursor', next);
        }
        return all;
    }

    public static Map<String, Object> doPost(String path, Map<String, Object> payload) {
        HttpRequest req = baseReq('POST', path);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        Map<String, Object> body = handle(new Http().send(req));
        return (Map<String, Object>) body.get('data');
    }

    public static Map<String, Object> doPatch(String path, Map<String, Object> payload, Integer ifMatchVersion) {
        HttpRequest req = baseReq('PATCH', path);
        req.setHeader('Content-Type', 'application/json');
        if (ifMatchVersion != null) req.setHeader('If-Match', String.valueOf(ifMatchVersion));
        req.setBody(JSON.serialize(payload));
        Map<String, Object> body = handle(new Http().send(req));
        return (Map<String, Object>) body.get('data');
    }
}
