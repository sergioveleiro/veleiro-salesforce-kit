@isTest
private class VeleiroTargetsTest {

    @isTest
    static void normalizeCanonicalizesKeys() {
        System.assertEquals('web_site', VeleiroTargets.normalize('  Web Site '));
        System.assertEquals('website', VeleiroTargets.normalize('WEBSITE'));
        System.assertEquals('sf_region', VeleiroTargets.normalize('sf_region'));
        System.assertEquals('a_b', VeleiroTargets.normalize('a---b'));
        System.assertEquals(null, VeleiroTargets.normalize(null));
    }

    @isTest
    static void suggestDerivesStableKey() {
        System.assertEquals('name', VeleiroTargets.suggest('Name'), 'Name -> top-level name');
        System.assertEquals('sf_website', VeleiroTargets.suggest('Website'));
        System.assertEquals('sf_my_field', VeleiroTargets.suggest('My_Field__c'));
        System.assertEquals('sf_region', VeleiroTargets.suggest('ns__Region__c'), 'quita namespace y __c');
        System.assertEquals('', VeleiroTargets.suggest(null));
    }

    @isTest
    static void typeInferredFromTarget() {
        System.assertEquals('Standard', VeleiroTargets.typeFor('client', 'name'));
        System.assertEquals('Additional Field', VeleiroTargets.typeFor('client', 'sf_website'));
        System.assert(!VeleiroTargets.canonical('client').isEmpty());
        System.assert(!VeleiroTargets.canonical('project').isEmpty());
        System.assert(VeleiroTargets.canonical('Case').isEmpty(), 'entidad desconocida -> sin catalogo');
    }
}
