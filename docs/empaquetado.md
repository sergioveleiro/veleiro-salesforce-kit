# Paquete administrado (managed package)

Cómo se construye y publica el kit como paquete administrado de 2ª generación.

## Las piezas y quién las tiene

| Pieza | Dónde vive | Notas |
|---|---|---|
| **Namespace** `veleiro` | Developer Edition `orgfarm-d4aa45f5ee-dev-ed` | **Permanente**. Registrado el 9/10/2026 por sergio@veleiro.ai. Si esta org muere, se pierde el prefijo. |
| **Dev Hub** | Veleiro Main (`veleiro-ai.my.salesforce.com`), Enterprise | Aquí viven el paquete y todas sus versiones. **No se puede mover a otro Dev Hub.** |
| **Paquete** | `Veleiro Salesforce Kit` · `0HoPe00000003SXKAY` | Managed, namespace `veleiro` |

**Riesgo a vigilar:** la Developer Edition del namespace se desactiva por inactividad (el registro menciona 45 días). Entrar al menos una vez al mes.

## La rama `packaging`

`main` es la versión **sin namespace**, que los partners despliegan desde el código fuente (Codeart, FastCloud, Veleiro Main). `packaging` es la misma base con lo que exige el empaquetado:

- `sfdx-project.json` con `"namespace": "veleiro"` y la definición del paquete.
- Las flexipages referencian `veleiro:veleiroDashboard` en vez de `c:veleiroDashboard`.
- Los tests resuelven el nombre del objeto del kit con `String.valueOf(Veleiro_Field_Mapping__c.SObjectType)`, porque bajo namespace pasa a ser `veleiro__Veleiro_Field_Mapping__c`.

Cualquier cambio funcional se hace en `main` y se trae a `packaging`. Cuando todos los clientes estén en el paquete administrado, `packaging` se vuelve `main`.

## No cambies de rama mientras se construye una versión

`sf package version create` escribe el alias de la versión nueva en `sfdx-project.json` **cuando termina**, sobre el archivo que haya en ese momento en el árbol de trabajo. Si entre tanto te moviste a `main`, los alias del paquete acaban en la rama que no es. Quédate en `packaging` hasta que el build termine, o revisa `git status` antes de commitear.

## Publicar una versión

```bash
git checkout packaging
git merge main                 # traer los cambios funcionales

# construir (tarda ~3 minutos; corre los tests y mide cobertura)
sf package version create --package "Veleiro Salesforce Kit" \
  --installation-key-bypass --code-coverage --target-dev-hub veleiro-ro --wait 45

# revisar cobertura (debe decir Code Coverage Met: true)
sf package version report --package <04t...> -v veleiro-ro

# probar en una org limpia ANTES de promover
sf org create scratch -f config/project-scratch-def.json --alias Pkg_Install_Test \
  --duration-days 3 --target-dev-hub veleiro-ro --no-namespace --wait 20
sf package install --package <04t...> -o Pkg_Install_Test --wait 20 --publish-wait 20 --no-prompt

# promover a released (IRREVERSIBLE: habilita instalar en producción)
sf package version promote --package <04t...> -v veleiro-ro
```

Una versión **no promovida** se puede instalar en scratch orgs y sandboxes, no en producción. Promover es definitivo: esa versión ya no se puede borrar ni modificar.

## Actualizar a un cliente

Hoy **no se puede empujar** una versión a la org de un cliente: eso es un *push upgrade* y requiere el programa de partners. Lo que sí funciona es mandarle el enlace de la versión nueva; Salesforce reconoce el paquete instalado y muestra *Upgrade* en vez de *Install*. Los datos, la configuración y los vínculos del cliente se conservan.

Dos condiciones para que eso ocurra:

1. **La versión debe estar promovida.** Sin promover no se instala en producción.
2. **Debe declarar ascendencia** (`"ancestorVersion": "HIGHEST"` en `sfdx-project.json`). Sin ancestro, Salesforce la trata como un paquete distinto y no deja actualizar.

**Numeración:** las versiones *patch* (1.0.**X**) requieren que Salesforce habilite patch versioning por caso en la Partner Community. Mientras tanto, el ciclo normal va por versiones menores: 1.1.0, 1.2.0, etc.

**Verificado el 12/10/2026:** una org con la 1.0.0.1 instalada se actualizó a la 1.1.0.1 por el mismo camino que usaría un cliente. La instalación mantuvo su identidad (mismo registro), los 3 flows siguieron activos, las 44 clases presentes y el permission set asignado.

**Verificado el 12/10/2026 (1.0.0.1 → 1.2.0.1), con datos de cliente:** se sembró en una org limpia lo que tendría un cliente trabajando — token, dirección `sf_to_veleiro`, winner `veleiro`, frecuencia `daily`, `Auto_Sync_Opportunity__c` apagado, 2 mapeos, una Account vinculada con versión 7 y un `Veleiro_Link__c` con versión 3 — y después del upgrade **todo quedó idéntico**, valor por valor. Al mismo tiempo llegó lo nuevo: el campo `Onboarding_Skipped__c`, las 3 clases nuevas, la pestaña `veleiro__Veleiro_Setup` y los 3 flows siguieron activos.

**Por qué no se pisa nada:** el paquete entrega *metadata* (objetos, campos, clases, pestañas); la configuración del cliente son *registros* (el custom setting `Veleiro_Config__c`, los `Veleiro_Field_Mapping__c`, los valores en `Account.Veleiro_Client_Id__c`, los `Veleiro_Link__c`). Un upgrade reemplaza metadata y nunca toca datos del suscriptor. El único punto donde un upgrade sí cambia comportamiento son los flows: si una versión modifica un flow, hay que subir el `activeVersionNumber` del `flowDefinition`. La 1.2.0 no tocó ningún flow.

## Historial de versiones

| Versión | Id de suscriptor | Cobertura | Estado |
|---|---|---|---|
| 1.0.0.1 | `04tPe0000010onRIAQ` | 93% | **Released** · primera versión · es la que tiene UMM-PRD |
| 1.1.0.1 | `04tPe0000010vc1IAA` | 93% | Beta · usada para probar la actualización. **Rama muerta**: nunca se promovió, así que una org con esta versión no puede subir a la 1.2.0 (son hermanas, no línea). |
| 1.2.0.1 | `04tPe0000010w6fIAA` | 94% | Released · **NO ENTREGAR**: arrastra el bug de la Named Credential. Sustituida por la 1.3.0.1. |
| 1.3.0.1 | `04tPe0000010w8HIAQ` | 94% | Released · arregla el callout. Superada por la 1.4.0.1. |
| 1.4.0.1 | `04tPe0000010w9tIAA` | 94% | Released · arregla los mapeos en blanco y el theme. Superada por la 1.5.0.1. |
| 1.5.0.1 | `04tPe0000010wBVIAY` | 94% | Released · pantallas a todo lo ancho y controles redondos. Superada por la 1.6.0.1. |
| 1.6.0.1 | `04tPe0000010yrdIAA` | 94% | **Released · la que se entrega hoy** · el project puede nacer al crear la oportunidad, solo al ganarla, o nunca sola |

## La trampa del namespace (nos costó dos versiones)

Todo lo que el paquete entrega vive bajo el namespace: el objeto es `veleiro__Veleiro_Field_Mapping__c`, la pestaña es `veleiro__Veleiro_Setup` y **la Named Credential es `veleiro__Veleiro_API`**. Un `callout:Veleiro_API` pelado falla con *"the named credential might not exist"*, que es lo que vio un cliente con la 1.0.0.1 instalada: el paquete nunca pudo hablar con Veleiro.

Lo peligroso es que **desde el código fuente no se reproduce**. Ahí el prefijo es vacío y el literal resulta correcto por casualidad, así que los tests pasan en `main` mientras el paquete está roto. Por eso:

- los nombres de metadata propia se arman en runtime con `VeleiroSyncConfig.namespacePrefix()`, nunca como literal;
- ese prefijo tiene una costura (`namespaceOverride`) y **todo lo que nombre metadata nuestra se prueba con el prefijo simulado**;
- antes de promover, vale más una prueba de callout real en una org con el paquete instalado que cien tests verdes en el código fuente.

**Verificado el 12/10/2026 (1.0.0.1 → 1.3.0.1):** en una org con la 1.0.0.1 y datos de cliente, crear una Account dispara el flow del paquete y el error que quedaba registrado era *"the named credential Veleiro_API might not exist"*. Tras el upgrade directo a la 1.3.0.1, el mismo camino registró *"invalid_token: The bearer token is missing or invalid"* — un error **de Veleiro**, o sea que el callout salió, llegó y fue respondido.

## Lo que el namespace rompe (van tres)

El prefijo `veleiro__` no solo afecta a los nombres que escribimos en el código. Hasta ahora nos mordió en tres formas distintas, todas invisibles desde el código fuente:

1. **Named Credentials.** `callout:Veleiro_API` no resuelve; es `veleiro__Veleiro_API`.
2. **Nombres de objeto en datos.** Un test que guarda `SObject__c = 'Veleiro_Field_Mapping__c'` no empata con el objeto real.
3. **sObjects que viajan al UI.** Un `@AuraEnabled` que devuelve el registro crudo serializa `veleiro__SObject__c`, y el componente que lee `m.SObject__c` recibe `undefined`. Un cliente lo vio como una lista de mapeos con todos los nombres en blanco.

La regla que sale de ahí: **nada que cruce la frontera del paquete se nombra con un literal.** Los campos viajan en DTOs con nombres propios, las credenciales y pestañas se arman con `VeleiroSyncConfig.namespacePrefix()`, y los tests simulan el prefijo. `VeleiroMappingControllerTest` asevera que el JSON que viaja al navegador **no contiene ningún `__c`**: esa sola línea es la que atrapa al siguiente que devuelva un sObject.

## El theme de la org no es nuestro

Una org puede traer un Lightning theme propio (UMM tiene uno). Un componente que hereda el fondo y el color del texto de la página se vuelve ilegible ahí. Cada raíz del kit pinta su propio lienzo (`--veleiro-canvas`) y su propio color (`--veleiro-ink`), y nunca asume que la página es clara.

## Un solo lugar para los clientes

El `04t` del enlace **es** la versión: cada release tiene su propio link y no existe uno que apunte "al último". Para que el cliente tenga una sola dirección, el enlace vive detrás de la página de descargas (`docs/descargas/`); al publicar una versión se actualiza ahí y nadie más se entera. La URL permanente de verdad es el listado de AppExchange, que llega con la revisión de seguridad — la misma que desbloquea los push upgrades.

## Los flows llegan activos (en el paquete, no desde el código fuente)

**Verificado el 13/10/2026** en una org recién creada con instalación limpia de la 1.5.0.1: los tres flows quedan `IsActive = true` sin que nadie los toque. Es lo contrario de un deploy desde código fuente, donde entran como Draft si el `flowDefinition` no fija la versión — el problema que tuvimos en Veleiro Main.

## En un paquete publicado no se puede cambiar el tipo de un campo

`Auto_Sync_Opportunity__c` nació Checkbox, y para darle un tercer estado hubo que **agregar** `Opportunity_Sync_Mode__c` en vez de convertirlo. El campo nuevo manda; en blanco se deduce del checkbox, así que una org configurada antes se comporta igual sin que nadie la toque, y `save()` mantiene el checkbox en sintonía para las orgs que todavía corran la versión anterior.

**Verificado el 13/10/2026 (1.5.0.1 → 1.6.0.1):** una org con el checkbox en `false` llegó al upgrade con el campo nuevo vacío y siguió sin sincronizar. Y con el modo en `won`, crear una oportunidad abierta no disparó ningún intento, mientras que pasarla a Closed Won sí llamó a Veleiro.

## Pendientes antes de entregar a un cliente en producción

1. **Verified Partner Business Org.** La pantalla de Package Manager avisa: para que los suscriptores instalen en **producción**, la org debe estar vinculada a una PBO verificada. Confirmar con el soporte de partners si aplica a 2GP.
2. **Push upgrades.** Confirmar si requieren partnership o revisión de seguridad. Era la razón principal para hacer el paquete administrado.
3. **Token en custom setting.** Ya empaquetado, `Veleiro_Config__c` puede pasar a `Protected`, que en un managed package **sí está permitido**. Eso cierra el hueco de que cualquier usuario con API pueda leer el token.
4. **Clientes actuales.** Codeart, FastCloud y Veleiro Main usan la versión sin namespace y **no se actualizan solas**: migrarlas implica instalar el paquete, trasladar vínculos y configuración, y luego quitar lo viejo.
