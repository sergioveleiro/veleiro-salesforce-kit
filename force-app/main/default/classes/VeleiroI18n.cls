/**
 * Textos del kit en el idioma del usuario (es / pt / en), para lo que se arma en Apex:
 * los pasos del setup y los mensajes de error que el UI muestra tal cual.
 *
 * Por que un diccionario y no Custom Labels: los labels viajan con el prefijo del namespace
 * dentro del paquete administrado, asi que la rama `packaging` tendria que reescribir cada
 * referencia, igual que ya hace con las flexipages. Un mapa por idioma se comporta igual en
 * las dos ramas y agregar un idioma es un bloque mas. Si algun dia un cliente necesita
 * cambiar los textos desde su propia org, ese es el momento de pasar a Custom Labels.
 *
 * El ingles es el respaldo llave por llave: una traduccion que falte no deja un hueco.
 */
public with sharing class VeleiroI18n {

    @TestVisible private static String languageOverride;   // para los tests

    // Idioma normalizado del usuario que esta corriendo: es | pt | en.
    public static String lang() {
        String l = (languageOverride != null) ? languageOverride : UserInfo.getLanguage();
        if (String.isBlank(l)) return 'en';
        l = l.toLowerCase();
        if (l.startsWith('es')) return 'es';
        if (l.startsWith('pt')) return 'pt';
        return 'en';
    }

    public static String t(String key) {
        String v = byLang().get(key);
        if (v == null) v = EN.get(key);
        return (v == null) ? key : v;      // nunca devuelve null: peor que un texto feo es un hueco
    }

    public static String t(String key, List<Object> args) {
        return String.format(t(key), args);
    }

    // Plural simple: la mayoria de las llaves solo cambian entre 1 y varios.
    public static String plural(Integer count, String oneKey, String manyKey) {
        return t(count == 1 ? oneKey : manyKey, new List<Object>{ count });
    }

    private static Map<String, String> byLang() {
        String l = lang();
        if (l == 'es') return ES;
        if (l == 'pt') return PT;
        return EN;
    }

    private static final Map<String, String> EN = new Map<String, String>{
        // --- pasos del setup ---
        'step.connection.title' => 'Connect your Veleiro account',
        'step.connection.summary' => 'Paste your Veleiro API token. Salesforce talks to Veleiro server to server: the token stays in your org and never reaches the browser.',
        'step.config.title' => 'Choose how it syncs',
        'step.config.summary' => 'Decide whether Salesforce pushes, pulls or both, and whether it happens when the record is created or only when you click Sync. Until you save this, the kit stays manual and touches nothing on its own.',
        'step.mapping.title' => 'Map your fields',
        'step.mapping.summary' => 'Pick which Salesforce object is a client or a project in Veleiro, and which field goes where. Without a mapping there is nothing to sync and nothing to link.',
        'step.link.title' => 'Bring your clients into Veleiro',
        'step.link.summary' => 'In the Veleiro Link tab you pick Salesforce records and they get created in Veleiro, many at a time. And if your clients already existed on both sides before the kit, that is where you match them instead of duplicating them.',
        'step.sync.title' => 'Sync your first account',
        'step.sync.summary' => 'Open an Account and hit Sync. It is the proof that the whole path works: Salesforce creates or updates the client in Veleiro and brings its version back.',
        'step.flows.title' => 'Turn on the automatic sync flows',
        'step.flows.summary' => 'You asked for automatic sync, and three flows do that work. In production flows install inactive: if you do not turn them on, nothing syncs by itself and no error is raised.',
        'step.team.title' => 'Give your team access',
        'step.team.summary' => 'The Veleiro Integration Access permission set is the only thing that grants access to the app, the fields and the panels. Without it a user signs in and sees nothing — including whoever installed the kit.',
        // --- evidencia ---
        'ev.connected' => 'Connected to Veleiro',
        'ev.tokenSaved' => 'Token saved',
        'ev.noToken' => 'The Veleiro token is missing',
        'ev.configUnsaved' => 'Not saved — manual for now',
        'ev.mappedField' => '{0} field mapped',
        'ev.mappedFields' => '{0} fields mapped',
        'ev.noMappings' => 'No field mapped yet',
        'ev.linkedRecord' => '{0} record linked',
        'ev.linkedRecords' => '{0} records linked',
        'ev.nothingLinked' => 'Nothing is in Veleiro yet',
        'ev.syncedRecord' => '{0} record synced',
        'ev.syncedRecords' => '{0} records synced',
        'ev.nothingSynced' => 'No record has travelled to Veleiro',
        'ev.flowsActive' => 'All 3 flows are active',
        'ev.flowsMissing' => 'I could not find the flows in this org',
        'ev.flowsInactive' => 'Inactive: {0}',
        'ev.flowsUnknown' => 'I could not check — this needs permission to view the org setup',
        'ev.teamNobody' => 'Not even you have it: without it you cannot see the Veleiro fields or the panels',
        'ev.teamOnlyYou' => 'Only you have it — your team still sees nothing',
        'ev.teamOther' => '{0} more person has access',
        'ev.teamOthers' => '{0} more people have access',
        'ev.teamUnknown' => 'I could not check the permission set assignments',
        // --- acciones ---
        'act.openMappings' => 'Open Veleiro Mappings',
        'act.openLink' => 'Open Veleiro Link',
        'act.myAccounts' => 'See my Accounts',
        'act.howToActivate' => 'How to turn them on',
        'act.assignPermset' => 'Assign the permission set',
        // --- configuracion, para resumirla ---
        'cfg.both' => 'Salesforce ⇄ Veleiro',
        'cfg.sfToVeleiro' => 'Salesforce → Veleiro',
        'cfg.veleiroToSf' => 'Veleiro → Salesforce',
        'cfg.auto' => 'automatic',
        'cfg.manual' => 'manual',
        // --- errores que el usuario lee tal cual ---
        'err.pushDisabled' => 'The configured direction is "Veleiro → Salesforce", so Salesforce cannot create anything in Veleiro. Change it in Veleiro Mappings to be able to send.',
        'err.noMapping' => 'There is no mapping for {0} → {1}. Set it up in Veleiro Mappings.',
        'err.batchTooBig' => 'That is {0} records and the limit per batch is {1}. Send one batch, wait for it to finish and continue with the next one.'
    };

    private static final Map<String, String> ES = new Map<String, String>{
        'step.connection.title' => 'Conecta tu cuenta de Veleiro',
        'step.connection.summary' => 'Pega el API token de Veleiro. Salesforce habla con Veleiro de servidor a servidor: el token se queda en tu org y nunca llega al navegador.',
        'step.config.title' => 'Elige cómo sincroniza',
        'step.config.summary' => 'Define si Salesforce empuja, jala o las dos, y si lo hace al crear el registro o solo cuando das clic. Mientras no lo guardes, el kit se queda en manual y no toca nada por su cuenta.',
        'step.mapping.title' => 'Mapea tus campos',
        'step.mapping.summary' => 'Elige qué objeto de Salesforce corresponde a un client o a un project en Veleiro, y qué campo va a dónde. Sin un mapeo no hay nada que sincronizar ni que vincular.',
        'step.link.title' => 'Trae tus clientes a Veleiro',
        'step.link.summary' => 'En la pestaña Veleiro Link eliges los registros de Salesforce y se crean en Veleiro, de a muchos. Y si tus clientes ya existían en los dos lados desde antes del kit, ahí mismo los emparejas en vez de duplicarlos.',
        'step.sync.title' => 'Sincroniza tu primera cuenta',
        'step.sync.summary' => 'Abre una Account y dale Sync. Es la prueba de que todo el camino funciona: Salesforce crea o actualiza el client en Veleiro y se trae su versión de vuelta.',
        'step.flows.title' => 'Activa los flows de sincronización automática',
        'step.flows.summary' => 'Pediste sincronización automática, y eso lo hacen tres flows. En producción los flows se instalan inactivos: si no los enciendes, nada se sincroniza solo y no sale ningún error.',
        'step.team.title' => 'Dale acceso a tu equipo',
        'step.team.summary' => 'El permission set Veleiro Integration Access es lo único que da acceso al app, a los campos y a los paneles. Sin él, un usuario entra y no ve nada — y eso incluye a quien instaló el kit.',
        'ev.connected' => 'Conectado a Veleiro',
        'ev.tokenSaved' => 'Token guardado',
        'ev.noToken' => 'Falta el token de Veleiro',
        'ev.configUnsaved' => 'Sin guardar — por ahora, manual',
        'ev.mappedField' => '{0} campo mapeado',
        'ev.mappedFields' => '{0} campos mapeados',
        'ev.noMappings' => 'Ningún campo mapeado todavía',
        'ev.linkedRecord' => '{0} registro vinculado',
        'ev.linkedRecords' => '{0} registros vinculados',
        'ev.nothingLinked' => 'Ningún registro está en Veleiro todavía',
        'ev.syncedRecord' => '{0} registro sincronizado',
        'ev.syncedRecords' => '{0} registros sincronizados',
        'ev.nothingSynced' => 'Ningún registro ha viajado a Veleiro',
        'ev.flowsActive' => 'Los 3 flows están activos',
        'ev.flowsMissing' => 'No encontré los flows en esta org',
        'ev.flowsInactive' => 'Inactivos: {0}',
        'ev.flowsUnknown' => 'No pude revisarlo — hace falta permiso para ver la configuración de la org',
        'ev.teamNobody' => 'Ni tú lo tienes: sin él no ves los campos de Veleiro ni los paneles',
        'ev.teamOnlyYou' => 'Solo tú lo tienes — tu equipo todavía no ve nada',
        'ev.teamOther' => '{0} persona más tiene acceso',
        'ev.teamOthers' => '{0} personas más tienen acceso',
        'ev.teamUnknown' => 'No pude revisar las asignaciones del permission set',
        'act.openMappings' => 'Abrir Veleiro Mappings',
        'act.openLink' => 'Abrir Veleiro Link',
        'act.myAccounts' => 'Ver mis Accounts',
        'act.howToActivate' => 'Cómo activarlos',
        'act.assignPermset' => 'Asignar el permission set',
        'cfg.both' => 'Salesforce ⇄ Veleiro',
        'cfg.sfToVeleiro' => 'Salesforce → Veleiro',
        'cfg.veleiroToSf' => 'Veleiro → Salesforce',
        'cfg.auto' => 'automático',
        'cfg.manual' => 'manual',
        'err.pushDisabled' => 'La dirección configurada es "Veleiro → Salesforce", así que Salesforce no puede crear nada en Veleiro. Cámbiala en Veleiro Mappings para poder enviar.',
        'err.noMapping' => 'No hay mapeo de {0} → {1}. Configúralo en Veleiro Mappings.',
        'err.batchTooBig' => 'Son {0} registros y el máximo por tanda es {1}. Manda una tanda, espera a que termine y sigue con la siguiente.'
    };

    private static final Map<String, String> PT = new Map<String, String>{
        'step.connection.title' => 'Conecte sua conta Veleiro',
        'step.connection.summary' => 'Cole o token de API do Veleiro. O Salesforce fala com o Veleiro de servidor para servidor: o token fica na sua org e nunca chega ao navegador.',
        'step.config.title' => 'Escolha como sincroniza',
        'step.config.summary' => 'Defina se o Salesforce envia, recebe ou os dois, e se isso acontece ao criar o registro ou só quando você clica em Sync. Enquanto não salvar, o kit fica no manual e não mexe em nada sozinho.',
        'step.mapping.title' => 'Mapeie seus campos',
        'step.mapping.summary' => 'Escolha qual objeto do Salesforce corresponde a um client ou a um project no Veleiro, e qual campo vai para onde. Sem mapeamento não há o que sincronizar nem o que vincular.',
        'step.link.title' => 'Traga seus clientes para o Veleiro',
        'step.link.summary' => 'Na aba Veleiro Link você escolhe os registros do Salesforce e eles são criados no Veleiro, vários de uma vez. E se seus clientes já existiam dos dois lados antes do kit, é ali que você os relaciona em vez de duplicá-los.',
        'step.sync.title' => 'Sincronize sua primeira conta',
        'step.sync.summary' => 'Abra uma Account e clique em Sync. É a prova de que todo o caminho funciona: o Salesforce cria ou atualiza o client no Veleiro e traz a versão dele de volta.',
        'step.flows.title' => 'Ative os flows de sincronização automática',
        'step.flows.summary' => 'Você pediu sincronização automática, e quem faz isso são três flows. Em produção os flows são instalados inativos: se você não ligá-los, nada sincroniza sozinho e nenhum erro aparece.',
        'step.team.title' => 'Dê acesso ao seu time',
        'step.team.summary' => 'O permission set Veleiro Integration Access é a única coisa que dá acesso ao app, aos campos e aos painéis. Sem ele o usuário entra e não vê nada — inclusive quem instalou o kit.',
        'ev.connected' => 'Conectado ao Veleiro',
        'ev.tokenSaved' => 'Token salvo',
        'ev.noToken' => 'Falta o token do Veleiro',
        'ev.configUnsaved' => 'Sem salvar — por enquanto, manual',
        'ev.mappedField' => '{0} campo mapeado',
        'ev.mappedFields' => '{0} campos mapeados',
        'ev.noMappings' => 'Nenhum campo mapeado ainda',
        'ev.linkedRecord' => '{0} registro vinculado',
        'ev.linkedRecords' => '{0} registros vinculados',
        'ev.nothingLinked' => 'Nenhum registro está no Veleiro ainda',
        'ev.syncedRecord' => '{0} registro sincronizado',
        'ev.syncedRecords' => '{0} registros sincronizados',
        'ev.nothingSynced' => 'Nenhum registro viajou para o Veleiro',
        'ev.flowsActive' => 'Os 3 flows estão ativos',
        'ev.flowsMissing' => 'Não encontrei os flows nesta org',
        'ev.flowsInactive' => 'Inativos: {0}',
        'ev.flowsUnknown' => 'Não consegui verificar — precisa de permissão para ver a configuração da org',
        'ev.teamNobody' => 'Nem você tem: sem ele você não vê os campos do Veleiro nem os painéis',
        'ev.teamOnlyYou' => 'Só você tem — seu time ainda não vê nada',
        'ev.teamOther' => 'mais {0} pessoa tem acesso',
        'ev.teamOthers' => 'mais {0} pessoas têm acesso',
        'ev.teamUnknown' => 'Não consegui verificar as atribuições do permission set',
        'act.openMappings' => 'Abrir Veleiro Mappings',
        'act.openLink' => 'Abrir Veleiro Link',
        'act.myAccounts' => 'Ver minhas Accounts',
        'act.howToActivate' => 'Como ativá-los',
        'act.assignPermset' => 'Atribuir o permission set',
        'cfg.both' => 'Salesforce ⇄ Veleiro',
        'cfg.sfToVeleiro' => 'Salesforce → Veleiro',
        'cfg.veleiroToSf' => 'Veleiro → Salesforce',
        'cfg.auto' => 'automático',
        'cfg.manual' => 'manual',
        'err.pushDisabled' => 'A direção configurada é "Veleiro → Salesforce", então o Salesforce não pode criar nada no Veleiro. Mude isso em Veleiro Mappings para poder enviar.',
        'err.noMapping' => 'Não há mapeamento de {0} → {1}. Configure em Veleiro Mappings.',
        'err.batchTooBig' => 'São {0} registros e o máximo por lote é {1}. Mande um lote, espere terminar e siga com o próximo.'
    };
}
