/**
 * Seeds the 6 default field mappings (Account & Opportunity) used by the mapping
 * console. Idempotent — deletes and re-inserts the defaults each run.
 *   sf apex run -o <your-org> -f scripts/apex/seedMappings.apex
 */
Integer n = VeleiroSeed.seed();
System.debug('Seeded ' + n + ' default field mappings.');
