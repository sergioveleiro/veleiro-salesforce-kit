@isTest
private class VeleiroI18nTest {

    @isTest
    static void everyLanguageResolvesToOneOfTheThree() {
        Map<String, String> cases = new Map<String, String>{
            'es' => 'es', 'es_MX' => 'es', 'ES_mx' => 'es',
            'pt_BR' => 'pt', 'pt' => 'pt',
            'en_US' => 'en', 'fr' => 'en', 'ja' => 'en', '' => 'en'
        };
        for (String given : cases.keySet()) {
            VeleiroI18n.languageOverride = given;
            System.assertEquals(cases.get(given), VeleiroI18n.lang(), 'idioma ' + given);
        }
        // null no es "sin idioma": es "sin override", y ahi manda el usuario de la org. Eso lo
        // cubre sinOverrideUsaElIdiomaDelUsuario, que no asume cual es.
    }

    @isTest
    static void thesameKeyReadsDifferentInEachLanguage() {
        VeleiroI18n.languageOverride = 'es';
        String es = VeleiroI18n.t('step.connection.title');
        VeleiroI18n.languageOverride = 'pt_BR';
        String pt = VeleiroI18n.t('step.connection.title');
        VeleiroI18n.languageOverride = 'en_US';
        String en = VeleiroI18n.t('step.connection.title');

        System.assertEquals('Conecta tu cuenta de Veleiro', es);
        System.assertEquals('Conecte sua conta Veleiro', pt);
        System.assertEquals('Connect your Veleiro account', en);
    }

    // Un hueco es peor que un texto en otro idioma: una llave desconocida devuelve la llave.
    @isTest
    static void anUnknownKeyNeverReturnsNull() {
        VeleiroI18n.languageOverride = 'pt';
        System.assertEquals('no.existe', VeleiroI18n.t('no.existe'));
    }

    @isTest
    static void placeholdersGetFilled() {
        VeleiroI18n.languageOverride = 'es';
        System.assertEquals('3 campos mapeados', VeleiroI18n.t('ev.mappedFields', new List<Object>{ 3 }));
        System.assertEquals('1 campo mapeado', VeleiroI18n.plural(1, 'ev.mappedField', 'ev.mappedFields'));
        System.assertEquals('2 campos mapeados', VeleiroI18n.plural(2, 'ev.mappedField', 'ev.mappedFields'));
    }

    @isTest
    static void sinOverrideUsaElIdiomaDelUsuario() {
        VeleiroI18n.languageOverride = null;
        String actual = VeleiroI18n.lang();
        System.assert(new Set<String>{ 'es', 'pt', 'en' }.contains(actual),
            'siempre cae en uno de los tres: ' + actual);
        System.assert(String.isNotBlank(VeleiroI18n.t('ev.connected')));
    }
}
