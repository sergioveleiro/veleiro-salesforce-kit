/**
 * Catalogo canonico de "targets" de Veleiro + normalizacion.
 *
 * Veleiro no tiene esquema para additional_fields: cualquier llave que mandes se
 * auto-crea como campo custom. Para no terminar con 5 variantes de lo mismo
 * (website / sf_website / web / homepage...), homologamos del lado del kit:
 *   - un catalogo canonico sugerido (sf_*) que la UI ofrece en un picklist,
 *   - normalizacion determinista de cualquier target al guardar,
 *   - una sugerencia estable a partir del campo de Salesforce (mismo campo SF ->
 *     misma llave en Veleiro, sin importar quien lo configure).
 */
public with sharing class VeleiroTargets {

    // Campos top-level escribibles por entidad. Todo lo demas vive en additional_fields.
    public static List<String> topLevel(String entity) {
        // 'name' es el unico top-level que Salesforce deberia dictar; status/progress/slug
        // son del lado de delivery (Veleiro) y no se empujan desde SF.
        return new List<String>{ 'name' };
    }

    // Catalogo canonico de additional_fields sugerido por entidad (homologa nombres).
    public static List<String> canonical(String entity) {
        if (entity == 'client') {
            return new List<String>{
                'sf_account_id', 'sf_account_name', 'sf_website', 'sf_industry', 'sf_phone',
                'sf_billing_city', 'sf_billing_country', 'sf_annual_revenue', 'sf_employees', 'sf_owner'
            };
        }
        if (entity == 'project') {
            return new List<String>{
                'sf_opportunity_id', 'sf_amount', 'sf_close_date', 'sf_stage',
                'sf_probability', 'sf_type', 'sf_owner'
            };
        }
        return new List<String>();
    }

    public static Boolean isTopLevel(String entity, String target) {
        return topLevel(entity).contains(target);
    }

    // El tipo se infiere del target: top-level conocido -> Standard; si no -> Additional Field.
    public static String typeFor(String entity, String target) {
        return isTopLevel(entity, target) ? 'Standard' : 'Additional Field';
    }

    // Normaliza a una llave canonica: minusculas, no-alfanumerico -> '_', colapsa/trim '_'.
    // 'Website ' / 'website' / 'web site' -> 'website' (una sola llave).
    public static String normalize(String raw) {
        if (String.isBlank(raw)) return raw;
        String s = raw.trim().toLowerCase();
        s = s.replaceAll('[^a-z0-9]+', '_');
        s = s.replaceAll('_+', '_');
        if (s.startsWith('_')) s = s.substring(1);
        if (s.endsWith('_')) s = s.substring(0, s.length() - 1);
        return s;
    }

    // Sugerencia canonica desde un campo de Salesforce: sf_<apiname normalizado>.
    // 'Name' -> 'name' (top-level); 'Website' -> 'sf_website'; 'ns__My_Field__c' -> 'sf_my_field'.
    public static String suggest(String sfField) {
        if (String.isBlank(sfField)) return '';
        String base = sfField;
        if (base.endsWithIgnoreCase('__c')) base = base.substring(0, base.length() - 3);
        if (base.contains('__')) base = base.substringAfterLast('__'); // quita namespace
        String norm = normalize(base);
        if (norm == 'name') return 'name';
        return 'sf_' + norm;
    }
}
