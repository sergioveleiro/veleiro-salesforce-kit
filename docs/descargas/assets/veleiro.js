  /* ---- idioma ----
     Los textos viven aqui y se inyectan en los elementos marcados con data-t. El espanol es
     la version de origen; ingles y portugues son traducciones, no transliteraciones. */
  var I18N = {
    es: {},
    en: {
      'eyebrow': 'Packages for Salesforce',
      'h1': 'Delivery, visible <em>from the CRM</em>',
      'lede': 'Two managed packages that install separately. One keeps accounts and opportunities in step with Veleiro clients and projects; the other lets anyone raise a ticket without leaving Salesforce.',
      'kit.role': 'Sales and delivery',
      'kit.sub': 'Account ⇄ client and opportunity ⇄ project, with the health of delivery where the seller already works.',
      'kit.f1': 'Manual or automatic sync, switchable for each pair',
      'kit.f2': 'Project progress on the opportunity and risk signals on the account',
      'kit.f3': 'Your own field mapping, and bulk linking of what already existed',
      'tkt.role': 'Support',
      'tkt.sub': 'A ticket raised from any Salesforce screen lands in Veleiro as a task, carrying its context.',
      'tkt.f1': 'A form in the utility bar, with attachments and the originating URL',
      'tkt.f2': 'Resend a ticket that never arrived, without typing it again',
      'tkt.f3': 'With the kit installed, it lands on the client or project of the record it came from',
      'btn.install': 'Install or upgrade',
      'btn.sandbox': 'Sandbox',
      'btn.code': 'Source',
      'spec.version': 'Latest version',
      'notice': '<b>The link always points at the latest version.</b> If your org already has an earlier one, Salesforce recognises the package and offers <b>Upgrade</b> instead of Install: your token, your mappings and your links are kept.',
      'steps.title': 'How the install goes',
      's1.t': 'Install the package',
      's1.d': 'From the link above, for admins or for all users.',
      's2.t': 'Assign the permission set',
      's2.d': '<code>Veleiro Integration Access</code>. Without it nobody sees the fields or the tabs — including whoever installed the package.',
      's3.t': 'Open Veleiro Setup',
      's3.d': 'It walks you through: token, how it syncs and the field mapping. Each step turns green only once it has really happened.',
      's4.t': 'Bring your clients in, then try it by hand',
      's4.d': 'In <b>Veleiro Link</b> you send your accounts to Veleiro, or match the ones that already existed on both sides. Sync two or three before turning on automatic mode.',
      'velly': 'Velly takes the helm. You choose the course.',
      'reqs.title': 'What you need before installing',
      'r1.t': 'A Veleiro token',
      'r1.d': 'Read and write on clients and projects.',
      'r2.t': 'A Salesforce user',
      'r2.d': 'Allowed to install packages and reach Setup.',
      'r3.t': 'Pick the environment',
      'r3.d': 'Veleiro production (<code>app.veleiro.ai</code>) or beta (<code>app.beta.veleiro.dev</code>). You can switch later without touching code.',
      'r4.t': 'What gets installed',
      'r4.d': 'Metadata only: Apex, components, fields prefixed <code>veleiro__</code> and a permission set. Nothing replaces or removes what your org already has.',
      'footer': 'Veleiro AI · managed packages under the <code>veleiro</code> namespace. Each one installs, upgrades and uninstalls on its own.',
      'sec.title': 'How safe it is to install',
      'sec.sub': 'This goes into a customer org, so what it does — and what it will not do — is deliberately bounded.',
      'sec1.t': 'The token never reaches the browser',
      'sec1.d': 'Every call to Veleiro leaves from Apex, server to server. No interface component receives it or displays it.',
      'sec2.t': 'Traffic leaves through a Named Credential',
      'sec2.d': 'The destination is declared in your Salesforce, not written inside the code. Your admin can see and control where traffic goes.',
      'sec3.t': 'Nobody sees anything until you allow it',
      'sec3.d': 'Installing leaves nothing visible. Access is granted with a permission set, user by user, and taken away just as fast.',
      'sec4.t': 'Metadata only',
      'sec4.d': 'Apex, components and fields prefixed <code>veleiro__</code>. It does not replace, delete or migrate anything your org already has.',
      'sec5.t': 'Brakes that protect your org',
      'sec5.d': 'Reading from Veleiro is bounded, a bulk load does not trigger syncs, and if one of your own rules rejects a record the batch carries on and the error stays visible.',
      'sec6.t': 'Tested and auditable',
      'sec6.d': 'Every class ships covered by tests and the package meets the coverage Salesforce requires to release a version. The source is public: you can read what it does before installing it.',
      'rel.title': 'Versions',
      'rel.sub': 'The link above always installs the most recent one. An org on an earlier version upgrades in place.',
      'rel.current': 'Current',
      'rel6.v': '1.6.0 · Oct 13, 2026',
      'rel6.n': 'The project can be born when the Opportunity is created, only once it is won, or never on its own. Account and Opportunity are configured separately.',
      'rel5.v': '1.5.0 · Oct 13, 2026',
      'rel5.n': 'The screens use the full width available and the controls take a pill shape.',
      'rel4.v': '1.4.0 · Oct 13, 2026',
      'rel4.n': 'The mapping list shows its names again, and the interface no longer depends on the theme the org happens to use.',
      'rel3.v': '1.3.0 · Oct 13, 2026',
      'rel3.n': 'Fixes the connection to Veleiro from inside the managed package.',
      'rel2.v': '1.2.0 · Oct 13, 2026',
      'rel2.n': 'Veleiro Setup tab, Veleiro Link in both directions, and the interface in Spanish, English and Portuguese.',
      'rel1.v': '1.0.0 · Oct 9, 2026',
      'rel1.n': 'First managed version.',
      'mp.title': 'What it means that this is a managed package',
      'mp.sub': 'It is not a zip of code someone hands you. It is a Salesforce distribution format with requirements of its own, and clearing them is the condition for being allowed to publish it at all.',
      'mp1.t': 'A namespace registered with Salesforce',
      'mp1.d': 'Everything that enters carries the <code>veleiro__</code> prefix, reserved under our name. That is why nothing can collide with a field, a class or a tab your org already has, even if they share a name.',
      'mp2.t': 'Salesforce will not publish it if it fails their checks',
      'mp2.d': 'Every version is built by running the whole test suite, and Salesforce measures the code coverage. Below their threshold the version is simply not created. It is not a promise from us: it is the gate you have to pass for the package to exist.',
      'mp3.t': 'It ships sealed, and that protects you too',
      'mp3.d': 'Its components cannot be edited from inside your org — not by us, not by anyone. What you installed is exactly what runs, and it changes only when you decide to upgrade.',
      'mp4.t': 'Versions with a line of succession',
      'mp4.d': 'Each version declares which one it comes from, and Salesforce only allows upgrades along that line. That is what guarantees an upgrade keeps your data instead of installing beside it.',
      'add.title': 'It installs by adding, never by changing',
      'add.sub': 'Installing it does not rearrange your Salesforce. It leaves you the pieces; where they go is your call.',
      'add1.t': 'It does not touch your pages or layouts',
      'add1.d': 'Your Account pages, your Opportunity pages and every other object stay exactly as they were. The package does not move, hide or reorder anything you already have.',
      'add2.t': 'You place the visual components yourself',
      'add2.d': 'The Veleiro panel on the account, the one on the opportunity and the sync buttons arrive available but switched off. Your admin drags them in Lightning App Builder onto the pages where they make sense, and removes them just as easily.',
      'add3.t': 'The app and its tabs arrive assembled',
      'add3.d': 'Veleiro Setup, Home, Mappings and Link come ready inside their own app, without mixing into the navigation your team already uses.',
      'add4.t': 'The rest is governed with permission sets',
      'add4.d': 'Who sees the app, the tabs and the fields is decided by assigning a permission set. No profiles are modified, and nothing hands permissions to anyone on its own.',
      'add5.t': 'Nothing is migrated or deleted',
      'add5.d': 'There are no scripts transforming your data on install. Your records stay yours, with the same values, before and after.',
      'nav.packages': 'Packages',
      'nav.security': 'Security',
      'nav.versions': 'Versions',
      'sec.eyebrow': 'Security',
      'sec.h1': 'What it does in your org, <em>and what it does not</em>',
      'sec.lede': 'This installs inside a customer\u2019s Salesforce. What it touches, what it sends out and who can see it are bounded on purpose, and written here without decoration.',
      'sec.token.title': 'How your token travels',
      'sec1.t': 'It never reaches the browser',
      'sec1.d': 'Every call to Veleiro leaves from Apex, server to server. No interface component receives it, and the panel only ever shows dots.',
      'sec2.t': 'It leaves through a Named Credential',
      'sec2.d': 'The destination is declared in your Salesforce, not written inside the code. Your admin can see and control where traffic goes, and cut it without touching anything else.',
      'sec3.t': 'You put it in, you take it out',
      'sec3.d': 'The token lives as data in your org; it does not ship inside the package. You paste it in the Veleiro Setup tab and delete it whenever you like \u2014 without it, the integration simply stops calling.',
      'sec.out.title': 'What data leaves your org',
      'sec.out.sub': 'Nothing travels on its own. Only what you mapped goes out, plus the keys that let a record be recognised on the way back.',
      'sec.out1.t': 'The fields you mapped',
      'sec.out1.d': 'Not one more. If you mapped name and website, that is what goes. You define the mapping in Veleiro Mappings and can change it whenever you want.',
      'sec.out2.t': 'Correlation keys',
      'sec.out2.d': 'The Salesforce record id \u2014 <code>sf_account_id</code>, <code>sf_opportunity_id</code>, <code>sf_record_id</code> \u2014 and the object name. That is what keeps clients from being duplicated and lets each record be recognised on the way back.',
      'sec.out3.t': 'No users, no attachments',
      'sec.out3.d': 'The kit does not send users, contacts, emails, files or history. If an object is not mapped, it does not exist for the integration.',
      'sec.in.title': 'What it writes inside your org',
      'sec.in1.t': 'The link',
      'sec.in1.d': 'Its own fields, prefixed <code>veleiro__</code>, holding the client or project id. They are new fields: nothing of yours is written over.',
      'sec.in2.t': 'It never renames your accounts',
      'sec.in2.d': 'Pulling from Veleiro does not overwrite an Account name unless you turn that switch on deliberately. It ships off.',
      'sec.in3.t': 'It respects your rules',
      'sec.in3.d': 'If one of your validation rules rejects a record, the integration does not work around it: that record is skipped, the rest of the batch carries on, and the error stays visible in the panel.',
      'sec.who.title': 'Who can see and do what',
      'sec4.t': 'Nobody, until you allow it',
      'sec4.d': 'Installing leaves nothing visible. Access is granted with a permission set, user by user, and withdrawn just as fast. No existing profiles or permissions are touched.',
      'sec5.t': 'It syncs when you say so',
      'sec5.d': 'It ships manual: nothing syncs by itself until you turn it on, and you can leave accounts automatic and opportunities by hand, or the other way around.',
      'sec6.t': 'Brakes so it cannot flood your org',
      'sec6.d': 'Reading from Veleiro is bounded per run, a bulk data load does not trigger syncs, and errors are recorded rather than swallowed.',
      'sec.what.title': 'What gets installed, exactly',
      'sec.what.sub': 'Metadata only. None of your data is replaced, deleted or migrated.',
      'cnt.apex': 'Apex classes',
      'cnt.lwc': 'interface components',
      'cnt.obj': 'objects of its own',
      'cnt.fld': 'fields on Account and Opportunity',
      'cnt.flow': 'sync flows',
      'cnt.ps': 'permission set',
      'sec.what.note': 'All under the <code>veleiro__</code> prefix, which is what guarantees it cannot collide with anything your org already has.',
      'sec.trust.title': 'How you can check all this',
      'sec.t1.t': 'Open source',
      'sec.t1.d': 'The repository is public. You can read exactly what it does before installing it, and review every change between versions.',
      'sec.t2.t': 'Tests on every class',
      'sec.t2.d': 'Every class ships covered by automated tests. Salesforce runs them while building each version and will not let it be published if coverage falls short.',
      'sec.t3.t': 'Try it in a sandbox',
      'sec.t3.d': 'The same link installs into a sandbox or a scratch org. Nothing forces you to meet it first in production.',
      'sec.t4.t': 'It uninstalls cleanly',
      'sec.t4.d': 'As a managed package it is removed from Setup and takes its components with it. Each package installs and uninstalls on its own.',
      'sec.cta.code': 'Read the code',
      'sec.cta.back': 'Back to the packages',
      'rel.eyebrow': 'Versions',
      'rel.h1': 'What changed, <em>and when</em>',
      'rel.lede': 'The install link always points at the most recent version. An org already on an earlier one upgrades in place, keeping its token, its mappings and its links.',
      'rel.how.title': 'How to upgrade',
      'rel.h1t': 'Open the install link',
      'rel.h1d': 'The one on the packages page, signed in to your org.',
      'rel.h2t': 'Salesforce recognises the package',
      'rel.h2d': 'If you already have an earlier version, the button says <b>Upgrade</b> instead of Install.',
      'rel.h3t': 'Your data stays put',
      'rel.h3d': 'Token, settings, mappings and links are kept: the upgrade replaces the code, not your data.',
      'rel.list.title': 'History',
      'rel6.date': 'October 13, 2026',
      'rel6.n': 'When the project is born is now a choice: with the Opportunity, only once it is won, or never on its own. Account and Opportunity are configured separately, for teams that sell first and deliver later.',
      'rel5.date': 'October 13, 2026',
      'rel5.n': 'The Setup and Link screens use the full width available, and fields and buttons take a pill shape.',
      'rel4.date': 'October 13, 2026',
      'rel4.n': 'The mapping list came back blank inside the package: fixed. And the interface stopped inheriting the org theme, so it looks the same whichever theme you run.',
      'rel3.date': 'October 13, 2026',
      'rel3.n': 'Fixes the connection to Veleiro from inside the managed package. Earlier versions could not complete the call.',
      'rel2.date': 'October 13, 2026',
      'rel2.n': 'Veleiro Setup tab with each step checked against the org itself, Veleiro Link in both directions \u2014 send to Veleiro and match what already exists \u2014 and the interface in Spanish, English and Portuguese following each user\u2019s own language.',
      'rel1.date': 'October 9, 2026',
      'rel1.n': 'First managed version: Account \u21c4 client, Opportunity \u21c4 project, field mapping and the delivery panel.',
      'rel.cta.install': 'Go and install it',
      'rel.cta.commits': 'See every change',
      'soon': 'Coming soon',
      'soon.note': 'Tell us if you want it early and we will turn it on for you.',
      'demo.title': 'See it working',
      'demo.sub': 'An interactive demo, not a video: click through it as if it were your own Salesforce.',
      'demo.launch': 'Launch interactive demo',
      'theme.toLight': 'Light theme',
      'theme.toDark': 'Dark theme'
    },
    pt: {
      'eyebrow': 'Pacotes para Salesforce',
      'h1': 'A entrega, visível <em>do CRM</em>',
      'lede': 'Dois pacotes gerenciados e independentes. Um mantém contas e oportunidades em sintonia com os clients e projects do Veleiro; o outro deixa qualquer pessoa abrir um ticket sem sair do Salesforce.',
      'kit.role': 'Vendas e entrega',
      'kit.sub': 'Account ⇄ client e opportunity ⇄ project, com a saúde da entrega onde o vendedor já trabalha.',
      'kit.f1': 'Sincronização manual ou automática, configurável para cada par',
      'kit.f2': 'Avanço do projeto na oportunidade e sinais de risco na conta',
      'kit.f3': 'Mapeamento de campos próprio e vinculação em massa do que já existia',
      'tkt.role': 'Suporte',
      'tkt.sub': 'Um ticket aberto de qualquer tela do Salesforce aparece como task no Veleiro, com o contexto dele.',
      'tkt.f1': 'Formulário na barra de utilidades, com anexos e a URL de origem',
      'tkt.f2': 'Reenvio de um ticket que não chegou, sem escrever tudo de novo',
      'tkt.f3': 'Com o kit instalado, cai no client ou project do registro de origem',
      'btn.install': 'Instalar ou atualizar',
      'btn.sandbox': 'Sandbox',
      'btn.code': 'Código',
      'spec.version': 'Versão mais recente',
      'notice': '<b>O link sempre aponta para a versão mais recente.</b> Se a sua org já tem uma anterior, o Salesforce reconhece o pacote e oferece <b>Upgrade</b> em vez de Install: seu token, seus mapeamentos e seus vínculos são mantidos.',
      'steps.title': 'Como é a instalação',
      's1.t': 'Instalar o pacote',
      's1.d': 'Pelo link acima, para administradores ou para todos os usuários.',
      's2.t': 'Atribuir o permission set',
      's2.d': '<code>Veleiro Integration Access</code>. Sem ele ninguém vê os campos nem as abas — inclusive quem instalou o pacote.',
      's3.t': 'Abra o Veleiro Setup',
      's3.d': 'Ela leva você passo a passo: token, como sincroniza e o mapeamento de campos. Cada passo fica verde só quando realmente aconteceu.',
      's4.t': 'Traga seus clientes e teste na mão',
      's4.d': 'No <b>Veleiro Link</b> você manda suas contas para o Veleiro, ou relaciona as que já existiam dos dois lados. Sincronize duas ou três antes de ligar o modo automático.',
      'velly': 'Velly leva o timão. Você escolhe o rumo.',
      'reqs.title': 'O que você precisa antes de instalar',
      'r1.t': 'Token do Veleiro',
      'r1.d': 'Leitura e escrita de clients e projects.',
      'r2.t': 'Usuário do Salesforce',
      'r2.d': 'Com permissão para instalar pacotes e entrar na Configuração.',
      'r3.t': 'Escolher o ambiente',
      'r3.d': 'Produção do Veleiro (<code>app.veleiro.ai</code>) ou beta (<code>app.beta.veleiro.dev</code>). Dá para mudar depois sem mexer em código.',
      'r4.t': 'O que é instalado',
      'r4.d': 'Somente metadados: Apex, componentes, campos com prefixo <code>veleiro__</code> e um permission set. Nada substitui nem apaga o que a org já tem.',
      'footer': 'Veleiro AI · pacotes gerenciados sob o namespace <code>veleiro</code>. Cada um instala, atualiza e desinstala por conta própria.',
      'sec.title': 'O quanto é seguro instalar',
      'sec.sub': 'Isto entra na org de um cliente, então o que faz — e o que não faz — é limitado de propósito.',
      'sec1.t': 'O token não chega ao navegador',
      'sec1.d': 'Cada chamada ao Veleiro sai do Apex, de servidor para servidor. Nenhum componente da interface recebe nem mostra o token.',
      'sec2.t': 'A saída passa por uma Named Credential',
      'sec2.d': 'O destino fica declarado no seu Salesforce, não escrito dentro do código. Seu administrador vê e controla para onde o tráfego sai.',
      'sec3.t': 'Ninguém vê nada até você permitir',
      'sec3.d': 'Instalar não deixa nada visível. O acesso é dado com um permission set, usuário por usuário, e é retirado com a mesma rapidez.',
      'sec4.t': 'Somente metadados',
      'sec4.d': 'Apex, componentes e campos com prefixo <code>veleiro__</code>. Não substitui, não apaga e não migra nada do que a sua org já tem.',
      'sec5.t': 'Freios para proteger a sua org',
      'sec5.d': 'A leitura do Veleiro é limitada, uma carga em massa não dispara sincronizações, e se uma regra sua rejeitar um registro o lote segue e o erro fica à vista.',
      'sec6.t': 'Testado e auditável',
      'sec6.d': 'Cada classe viaja coberta por testes e o pacote cumpre a cobertura que o Salesforce exige para publicar uma versão. O código é público: dá para ler o que ele faz antes de instalar.',
      'rel.title': 'Versões',
      'rel.sub': 'O link acima sempre instala a mais recente. Uma org com uma versão anterior é atualizada no mesmo lugar.',
      'rel.current': 'Atual',
      'rel6.v': '1.6.0 · 13 out 2026',
      'rel6.n': 'O project pode nascer ao criar a oportunidade, só quando ela é ganha, ou nunca sozinho. Account e Opportunity são configurados separadamente.',
      'rel5.v': '1.5.0 · 13 out 2026',
      'rel5.n': 'As telas usam toda a largura disponível e os controles ganham formato de pílula.',
      'rel4.v': '1.4.0 · 13 out 2026',
      'rel4.n': 'A lista de mapeamentos volta a mostrar os nomes, e a interface não depende mais do tema que a org usa.',
      'rel3.v': '1.3.0 · 13 out 2026',
      'rel3.n': 'Corrige a conexão com o Veleiro dentro do pacote gerenciado.',
      'rel2.v': '1.2.0 · 13 out 2026',
      'rel2.n': 'Aba Veleiro Setup, Veleiro Link nas duas direções, e interface em espanhol, inglês e português.',
      'rel1.v': '1.0.0 · 9 out 2026',
      'rel1.n': 'Primeira versão gerenciada.',
      'mp.title': 'O que significa ser um pacote gerenciado',
      'mp.sub': 'Não é um zip de código que alguém te passa. É um formato de distribuição do Salesforce com exigências próprias, e cumpri-las é a condição para poder publicá-lo.',
      'mp1.t': 'Namespace registrado no Salesforce',
      'mp1.d': 'Tudo o que entra leva o prefixo <code>veleiro__</code>, reservado em nosso nome. É por isso que nada pode colidir com um campo, uma classe ou uma aba que a sua org já tenha, mesmo com o mesmo nome.',
      'mp2.t': 'O Salesforce não publica se não passar nos testes dele',
      'mp2.d': 'Cada versão é construída rodando toda a bateria de testes, e o Salesforce mede a cobertura do código. Abaixo do limite dele, a versão simplesmente não é criada. Não é uma promessa nossa: é o portão por onde é preciso passar para o pacote existir.',
      'mp3.t': 'Vai lacrado, e isso também protege você',
      'mp3.d': 'Os componentes não podem ser editados de dentro da sua org — nem por nós, nem por ninguém. O que você instalou é exatamente o que roda, e muda só quando você decide atualizar.',
      'mp4.t': 'Versões com linha de sucessão',
      'mp4.d': 'Cada versão declara de qual veio, e o Salesforce só permite atualizar seguindo essa linha. É o que garante que uma atualização preserve seus dados em vez de se instalar ao lado.',
      'add.title': 'Instala somando, nunca mudando',
      'add.sub': 'Instalar não reorganiza o seu Salesforce. Ele te deixa as peças; onde elas vão é decisão sua.',
      'add1.t': 'Não mexe nas suas páginas nem nos seus layouts',
      'add1.d': 'Suas páginas de Account, de Opportunity e de qualquer outro objeto ficam exatamente como estavam. O pacote não move, não esconde e não reordena nada do que você já tem.',
      'add2.t': 'Os componentes visuais quem coloca é você',
      'add2.d': 'O painel do Veleiro na conta, o da oportunidade e os botões de sincronizar chegam disponíveis, mas desligados. Seu administrador arrasta eles no Lightning App Builder para as páginas onde fizerem sentido, e tira com a mesma facilidade.',
      'add3.t': 'O app e as abas chegam montados',
      'add3.d': 'Veleiro Setup, Home, Mappings e Link vêm prontos dentro do próprio app, sem se misturar à navegação que o seu time já usa.',
      'add4.t': 'O resto é governado por permission sets',
      'add4.d': 'Quem vê o app, as abas e os campos se decide atribuindo um permission set. Nenhum perfil é modificado, e nada distribui permissões por conta própria.',
      'add5.t': 'Nada é migrado nem apagado',
      'add5.d': 'Não há scripts transformando seus dados na instalação. Seus registros continuam seus, com os mesmos valores, antes e depois.',
      'nav.packages': 'Pacotes',
      'nav.security': 'Segurança',
      'nav.versions': 'Versões',
      'sec.eyebrow': 'Segurança',
      'sec.h1': 'O que ele faz na sua org, <em>e o que não faz</em>',
      'sec.lede': 'Isto é instalado dentro do Salesforce de um cliente. O que ele toca, o que manda para fora e quem pode ver está limitado de propósito, e está escrito aqui sem enfeite.',
      'sec.token.title': 'Como o seu token viaja',
      'sec1.t': 'Nunca chega ao navegador',
      'sec1.d': 'Cada chamada ao Veleiro sai do Apex, de servidor para servidor. Nenhum componente da interface recebe o token, e o painel só mostra pontinhos.',
      'sec2.t': 'Sai por uma Named Credential',
      'sec2.d': 'O destino fica declarado no seu Salesforce, não escrito dentro do código. Seu administrador vê e controla para onde o tráfego sai, e pode cortar sem mexer em mais nada.',
      'sec3.t': 'Você coloca e você tira',
      'sec3.d': 'O token vive como dado na sua org; não vem dentro do pacote. Você cola na aba Veleiro Setup e apaga quando quiser — sem ele, a integração simplesmente para de chamar.',
      'sec.out.title': 'Quais dados saem da sua org',
      'sec.out.sub': 'Nada viaja por conta própria. Só sai o que você mapeou, mais as chaves que permitem reconhecer o registro na volta.',
      'sec.out1.t': 'Os campos que você mapeou',
      'sec.out1.d': 'Nem um a mais. Se você mapeou nome e site, é isso que sai. O mapeamento é definido por você em Veleiro Mappings e dá para mudar quando quiser.',
      'sec.out2.t': 'Chaves de correlação',
      'sec.out2.d': 'O id do registro do Salesforce — <code>sf_account_id</code>, <code>sf_opportunity_id</code>, <code>sf_record_id</code> — e o nome do objeto. É o que evita duplicar clients e permite reconhecer cada registro na volta.',
      'sec.out3.t': 'Nada de usuários nem anexos',
      'sec.out3.d': 'O kit não manda usuários, contatos, e-mails, arquivos nem histórico. Se um objeto não está mapeado, ele não existe para a integração.',
      'sec.in.title': 'O que ele escreve dentro da sua org',
      'sec.in1.t': 'O vínculo',
      'sec.in1.d': 'Campos próprios com prefixo <code>veleiro__</code> guardando o id do client ou project. São campos novos: nada do que é seu é sobrescrito.',
      'sec.in2.t': 'Nunca renomeia suas contas',
      'sec.in2.d': 'Trazer dados do Veleiro não sobrescreve o nome de uma Account, a menos que você ligue essa chave de propósito. Ela vem desligada.',
      'sec.in3.t': 'Respeita as suas regras',
      'sec.in3.d': 'Se uma validation rule sua rejeita um registro, a integração não passa por cima: esse registro é pulado, o resto do lote continua e o erro fica visível no painel.',
      'sec.who.title': 'Quem pode ver e fazer o quê',
      'sec4.t': 'Ninguém, até você permitir',
      'sec4.d': 'Instalar não deixa nada visível. O acesso é dado com um permission set, usuário por usuário, e retirado com a mesma rapidez. Nenhum perfil ou permissão existente é tocado.',
      'sec5.t': 'Sincroniza quando você mandar',
      'sec5.d': 'Vem no manual: nada sincroniza sozinho até você ligar, e dá para deixar as contas no automático e as oportunidades na mão, ou o contrário.',
      'sec6.t': 'Freios para não afogar a sua org',
      'sec6.d': 'A leitura do Veleiro é limitada por rodada, uma carga em massa de dados não dispara sincronizações, e os erros são registrados em vez de engolidos.',
      'sec.what.title': 'O que é instalado, exatamente',
      'sec.what.sub': 'Somente metadados. Nenhum dado seu é substituído, apagado ou migrado.',
      'cnt.apex': 'classes Apex',
      'cnt.lwc': 'componentes de interface',
      'cnt.obj': 'objetos próprios',
      'cnt.fld': 'campos em Account e Opportunity',
      'cnt.flow': 'flows de sincronização',
      'cnt.ps': 'permission set',
      'sec.what.note': 'Tudo sob o prefixo <code>veleiro__</code>, que é o que garante que não colida com nada que a sua org já tenha.',
      'sec.trust.title': 'Como você pode conferir tudo isso',
      'sec.t1.t': 'Código aberto',
      'sec.t1.d': 'O repositório é público. Dá para ler exatamente o que ele faz antes de instalar, e revisar cada mudança entre versões.',
      'sec.t2.t': 'Testes em cada classe',
      'sec.t2.d': 'Cada classe viaja coberta por testes automatizados. O Salesforce roda esses testes ao construir cada versão e não deixa publicá-la se a cobertura não alcançar.',
      'sec.t3.t': 'Teste num sandbox',
      'sec.t3.d': 'O mesmo link instala num sandbox ou numa scratch org. Nada obriga você a conhecê-lo primeiro em produção.',
      'sec.t4.t': 'Desinstala limpo',
      'sec.t4.d': 'Como pacote gerenciado, é removido pelo Setup e leva seus componentes junto. Cada pacote instala e desinstala por conta própria.',
      'sec.cta.code': 'Ler o código',
      'sec.cta.back': 'Voltar aos pacotes',
      'rel.eyebrow': 'Versões',
      'rel.h1': 'O que mudou, <em>e quando</em>',
      'rel.lede': 'O link de instalação sempre aponta para a versão mais recente. Uma org que já tem uma anterior é atualizada no mesmo lugar, mantendo seu token, seus mapeamentos e seus vínculos.',
      'rel.how.title': 'Como atualizar',
      'rel.h1t': 'Abra o link de instalação',
      'rel.h1d': 'O mesmo da página de pacotes, com a sessão iniciada na sua org.',
      'rel.h2t': 'O Salesforce reconhece o pacote',
      'rel.h2d': 'Se você já tem uma versão anterior, o botão diz <b>Upgrade</b> em vez de Install.',
      'rel.h3t': 'Seus dados continuam lá',
      'rel.h3d': 'Token, configuração, mapeamentos e vínculos são mantidos: a atualização troca o código, não os seus dados.',
      'rel.list.title': 'Histórico',
      'rel6.date': '13 de outubro, 2026',
      'rel6.n': 'Quando o project nasce agora é escolha sua: ao criar a oportunidade, só quando ela é ganha, ou nunca sozinho. Account e Opportunity são configurados separadamente, para os times que vendem primeiro e entregam depois.',
      'rel5.date': '13 de outubro, 2026',
      'rel5.n': 'As telas de Setup e Link usam toda a largura disponível, e campos e botões ganham formato de pílula.',
      'rel4.date': '13 de outubro, 2026',
      'rel4.n': 'A lista de mapeamentos voltava em branco dentro do pacote: corrigido. E a interface deixou de herdar o tema da org, então fica igual com qualquer tema.',
      'rel3.date': '13 de outubro, 2026',
      'rel3.n': 'Corrige a conexão com o Veleiro dentro do pacote gerenciado. As versões anteriores não conseguiam completar a chamada.',
      'rel2.date': '13 de outubro, 2026',
      'rel2.n': 'Aba Veleiro Setup com cada passo verificado contra a própria org, Veleiro Link nas duas direções — enviar ao Veleiro e relacionar o que já existe — e interface em espanhol, inglês e português conforme o idioma de cada usuário.',
      'rel1.date': '9 de outubro, 2026',
      'rel1.n': 'Primeira versão gerenciada: Account ⇄ client, Opportunity ⇄ project, mapeamento de campos e o painel de entrega.',
      'rel.cta.install': 'Ir instalar',
      'rel.cta.commits': 'Ver cada mudança',
      'soon': 'Em breve',
      'soon.note': 'Avise se quiser testar antes e a gente libera para você.',
      'demo.title': 'Veja funcionando',
      'demo.sub': 'Uma demo interativa, não um vídeo: clique como se fosse o seu próprio Salesforce.',
      'demo.launch': 'Abrir a demo interativa',
      'theme.toLight': 'Tema claro',
      'theme.toDark': 'Tema escuro'
    }
  };

  (function () {
    var root = document.documentElement;

    /* ---- idioma ----
       El espanol vive en el propio HTML, asi que es-ES se arma leyendo la pagina al cargar:
       una traduccion que falte deja el texto original, nunca un hueco. */
    var nodes = [].slice.call(document.querySelectorAll('[data-t]'));
    nodes.forEach(function (el) {
      var key = el.getAttribute('data-t');
      if (!(key in I18N.es)) I18N.es[key] = el.innerHTML;
    });
    I18N.es['demo.launch'] = 'Abrir la demo interactiva';
    I18N.es['theme.toLight'] = 'Tema claro';
    I18N.es['theme.toDark'] = 'Tema oscuro';

    var langButtons = [].slice.call(document.querySelectorAll('.lang button'));
    var lang = 'es';

    function applyLang(next) {
      lang = I18N[next] ? next : 'es';
      var dict = I18N[lang];
      nodes.forEach(function (el) {
        var value = dict[el.getAttribute('data-t')];
        if (value !== undefined) el.innerHTML = value;
      });
      // El rotulo del boton de la demo vive dentro del iframe: solo se puede cambiar por URL.
      // Se reescribe solo si cambio, para no recargar el embed en cada repintado.
      var frame = document.getElementById('howdygo-frame');
      if (frame) {
        var wanted = frame.src.replace(/launchButton=[^&]*/,
          'launchButton=' + encodeURIComponent(dict['demo.launch'] || 'Launch interactive demo'));
        if (wanted !== frame.src) frame.src = wanted;
      }
      root.setAttribute('lang', lang);
      langButtons.forEach(function (b) {
        b.setAttribute('aria-pressed', b.getAttribute('data-lang') === lang ? 'true' : 'false');
      });
      paintThemeLabel();
    }

    function preferredLang() {
      var saved = null;
      try { saved = localStorage.getItem('veleiro-lang'); } catch (e) { /* sin almacenamiento */ }
      if (I18N[saved]) return saved;
      var nav = (navigator.language || 'es').toLowerCase();
      if (nav.indexOf('pt') === 0) return 'pt';
      if (nav.indexOf('es') === 0) return 'es';
      return 'en';
    }

    langButtons.forEach(function (b) {
      b.addEventListener('click', function () {
        var next = b.getAttribute('data-lang');
        applyLang(next);
        try { localStorage.setItem('veleiro-lang', next); } catch (e) { /* no se recuerda */ }
      });
    });

    /* ---- tema ----
       Claro por defecto: la pagina es la cara del producto y debe abrir siempre igual.
       El oscuro existe para quien lo pida, no porque su sistema este en oscuro. */
    var btn = document.getElementById('themeToggle');
    var label = document.getElementById('themeLabel');

    function currentTheme() {
      return root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
    }
    function paintThemeLabel() {
      var dict = I18N[lang] || I18N.es;
      var key = currentTheme() === 'dark' ? 'theme.toLight' : 'theme.toDark';
      label.textContent = dict[key] || label.textContent;
    }
    function applyTheme(theme) {
      root.setAttribute('data-theme', theme);
      btn.setAttribute('aria-pressed', theme === 'dark' ? 'true' : 'false');
      paintThemeLabel();
    }

    var savedTheme = null;
    try { savedTheme = localStorage.getItem('veleiro-theme'); } catch (e) { /* sin almacenamiento */ }
    applyTheme(savedTheme === 'dark' ? 'dark' : 'light');

    btn.addEventListener('click', function () {
      var next = currentTheme() === 'dark' ? 'light' : 'dark';
      applyTheme(next);
      try { localStorage.setItem('veleiro-theme', next); } catch (e) { /* no se recuerda */ }
    });

    applyLang(preferredLang());
  })();
