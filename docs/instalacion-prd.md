# Instalación en producción — Veleiro Salesforce Kit

Guía paso a paso, del ZIP a los flows activos. Escrita para quien instala el kit en una org de producción (probada en Veleiro Main / `veleiro-ro`).

## 0. Antes de empezar

1. **Token de Veleiro** con permisos de lectura y escritura en clients y projects. El token es distinto en producción (`app.veleiro.ai`) y en beta (`app.beta.veleiro.dev`).
2. **Decide el ambiente** al que va a apuntar la org: producción o beta.
3. **Usuario de Salesforce** con permiso para desplegar y para "Customize Application".

## 1. Bajar el código

- https://github.com/sergioveleiro/veleiro-salesforce-kit → botón **Code** → **Download ZIP** (rama `main`).
- Descomprime. Lo único que se despliega es la carpeta **`force-app/`**.
- Verifica que el ZIP traiga la pestaña **Veleiro Link** (`force-app/main/default/lwc/veleiroLinkHome`). Si no está, el ZIP es viejo.

## 2. Desplegar

### A) Desde la plataforma de Veleiro

1. Abre el modal de deploy y elige la conexión de la org.
2. **Run tests:** activado (obligatorio en producción).
3. **Test level: Run specified tests.** Nunca "Run local tests": corre los tests de toda la org y otros proyectos pueden bloquear el deploy.
4. Pega esta lista de tests:

```
VeleiroApiClientTest, VeleiroClientMatcherTest, VeleiroConnectionTest, VeleiroDashboardControllerTest, VeleiroInsightServiceTest, VeleiroLinkControllerTest, VeleiroMappingControllerTest, VeleiroOppSyncQueueableTest, VeleiroSeedTest, VeleiroSyncConfigTest, VeleiroSyncServiceTest, VeleiroSyncTest, VeleiroTargetsTest
```

5. Deja **Rollback on error** activado y **Deploy all metadata**.
6. La primera vez conviene marcar **Validate only** (prueba que no guarda nada) y luego repetir sin esa marca.

### B) Desde la terminal

```bash
scripts/deploy.sh <alias-org> --validate   # prueba, no guarda nada
scripts/deploy.sh <alias-org>              # deploy real
```

## 3. Dar acceso

```bash
sf org assign permset -o <alias-org> -n Veleiro_Integration_Access
```

O en Setup → **Permission Sets** → **Veleiro Integration Access** → **Manage Assignments**. Asígnalo a todos los usuarios que vayan a ver o sincronizar datos de Veleiro.

## 4. Conectar con Veleiro

App Launcher → **Veleiro** → pestaña **Veleiro Mappings**.

1. En el bloque de conexión, pega el **token** y guarda.
2. Elige el **ambiente**: Production o Beta. Eso ajusta solo las URLs; el token no se toca.
3. Pulsa refrescar (↻). Debe quedar verde con "Connected to Veleiro".

> El README todavía dice que para ir a beta hay que editar el Named Credential. Eso quedó viejo: hoy se cambia desde este panel.

## 5. Definir cómo se comporta la integración

En el mismo panel, sección **1 · How the integration works**:

- **Direction:** Bidirectional, o solo Salesforce → Veleiro.
- **On conflict, who wins:** normalmente Salesforce.
- **Pull from Veleiro:** Off, cada hora o diario.
- **Sync to Veleiro (trigger):** **Automatic on record create** si quieres que los flows funcionen. En "Manual" no se sincroniza nada solo.
- **Save configuration**.

## 6. Cargar los mapeos de campos

En la sección **2 · Field Mappings**, si está vacía, usa la plantilla por defecto y guarda. Desde la terminal:

```bash
sf apex run -o <alias-org> -f scripts/apex/seedMappings.apex
```

Revisa que **Account → Client** incluya `Website`: sin sitio web, Veleiro no lanza el análisis del cliente.

## 7. Activar los flows (Setup → Flows)

Estos 3 deben quedar en **Active**. En producción llegan activos solo porque el paquete trae los archivos `flowDefinitions`; si alguno aparece en Draft, actívalo a mano con **Activate**:

| Flow | Qué hace |
|---|---|
| **Auto Sync Account On Create** | Crea el client en Veleiro al crear un Account y, con Website, dispara el análisis. |
| **Auto Sync Opportunity On Create** | Crea el project al crear una Opportunity. |
| **Create Veleiro Project On Closed Won** | Crea el project cuando la Opportunity pasa a Closed Won. |

Los 3 solo actúan si el trigger del paso 5 está en **Automatic**.

## 7b. Vincular lo que ya existía (solo si la org tiene historia)

Si esa org ya tenía Accounts en Salesforce y clients en Veleiro creados antes del kit, abre la pestaña **Veleiro Link** *antes* de sincronizar:

1. La pantalla cruza los Accounts sin vincular contra los clients de Veleiro.
2. Las coincidencias fuertes (mismo id de Account o mismo dominio) vienen marcadas; las de solo nombre hay que revisarlas.
3. Dos formas de aplicar:
   - **Link and sync** (recomendado): vincula y además manda a Veleiro los campos mapeados de cada cuenta y el id de Salesforce. Corre en segundo plano.
   - **Link**: solo vincula, sin tocar Veleiro. Útil si aún no quieres enviar datos.
4. Nada se crea en Veleiro: los clients ya existían.

## 8. Poner los componentes en las páginas (App Builder)

- **Página de Account:** agrega **Veleiro** (`veleiroPanel`) y **Velly Insight** (`veleiroInsight`).
- **Página de Opportunity:** agrega **Veleiro Project** (`veleiroOppPanel`).
- **Acciones de página:** agrega `veleiroSyncAction` en Account y `veleiroSyncOppAction` en Opportunity, desde "Mobile & Lightning Actions".
- **Navegación:** agrega los tabs **Veleiro Home**, **Veleiro Mappings** y **Veleiro Link** a tu app, o usa la app **Veleiro** que ya viene lista.

## 9. Probar de punta a punta

1. **Manual:** abre un Account y pulsa **Sync with Veleiro**. El panel debe mostrar "Synced" y el link a Veleiro.
2. **Automático:** crea un Account nuevo **con Website**. En un minuto debería aparecer el client en Veleiro, con el análisis corriendo.
3. **Conversión de Lead:** convierte un Lead con empresa y Website. Debe crear **un solo** client, más el project de la Opportunity.
4. **Closed Won:** pasa una Opportunity a Closed Won y verifica que se cree el project.
5. Busca siempre en el ambiente configurado: si es beta, en `app.beta.veleiro.dev`.

## Si algo falla

- **"You can't set the visibility for a Custom Setting to Protected":** el ZIP es viejo; baja `main` otra vez.
- **Falla un test que no es del kit:** el deploy corrió con "Run local tests". Repite con "Run specified tests" y la lista del paso 2.
- **Se creó el Account pero no llegó a Veleiro:** revisa en orden que el trigger esté en Automatic, que los 3 flows estén activos y que la conexión esté verde. Si el sync falla, hoy el error no se muestra en ningún lado (pendiente abierto).
- **No se lanzó el análisis del cliente:** el Account no tenía Website, o el client ya existía. El análisis solo se dispara al crear el client.

## Por qué producción se comporta distinto a sandbox

Tres diferencias que costaron un deploy fallido cada una:

1. **Custom Setting `Protected`** solo se permite en developer, sandbox y scratch orgs. `Veleiro_Config__c` ahora es `Public`.
2. **Los flows se despliegan inactivos** en producción, aunque el archivo diga `Active`. Por eso cada flow necesita su `flowDefinitions/<Flow>.flowDefinition-meta.xml`. Ese archivo fija el número de versión: si cambias un flow que ya está activo en una org, hay que subirlo.
3. **`RunLocalTests` corre los tests de toda la org**, así que tests ajenos al kit pueden bloquear el deploy.

## Paquete aparte: ticket intake

https://github.com/sergioveleiro/veleiro-ticket-intake es otro producto, con su propia instalación, su propio token y su propio permission set (`Veleiro_Ticket_Intake_User`). Se instala igual, con "Run specified tests" y:

```
VeleiroTicketControllerTest, VeleiroTicketRoutingTest, VeleiroTicketServiceTest
```

Los dos paquetes conviven en la misma org sin chocar.
