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
| 1.3.0.1 | `04tPe0000010w8HIAQ` | 94% | **Released · la que se entrega hoy** · arregla el callout + pestaña Veleiro Setup, Veleiro Link en dos direcciones, idiomas es/pt/en |

## La trampa del namespace (nos costó dos versiones)

Todo lo que el paquete entrega vive bajo el namespace: el objeto es `veleiro__Veleiro_Field_Mapping__c`, la pestaña es `veleiro__Veleiro_Setup` y **la Named Credential es `veleiro__Veleiro_API`**. Un `callout:Veleiro_API` pelado falla con *"the named credential might not exist"*, que es lo que vio un cliente con la 1.0.0.1 instalada: el paquete nunca pudo hablar con Veleiro.

Lo peligroso es que **desde el código fuente no se reproduce**. Ahí el prefijo es vacío y el literal resulta correcto por casualidad, así que los tests pasan en `main` mientras el paquete está roto. Por eso:

- los nombres de metadata propia se arman en runtime con `VeleiroSyncConfig.namespacePrefix()`, nunca como literal;
- ese prefijo tiene una costura (`namespaceOverride`) y **todo lo que nombre metadata nuestra se prueba con el prefijo simulado**;
- antes de promover, vale más una prueba de callout real en una org con el paquete instalado que cien tests verdes en el código fuente.

**Verificado el 12/10/2026 (1.0.0.1 → 1.3.0.1):** en una org con la 1.0.0.1 y datos de cliente, crear una Account dispara el flow del paquete y el error que quedaba registrado era *"the named credential Veleiro_API might not exist"*. Tras el upgrade directo a la 1.3.0.1, el mismo camino registró *"invalid_token: The bearer token is missing or invalid"* — un error **de Veleiro**, o sea que el callout salió, llegó y fue respondido.

## Pendientes antes de entregar a un cliente en producción

1. **Verified Partner Business Org.** La pantalla de Package Manager avisa: para que los suscriptores instalen en **producción**, la org debe estar vinculada a una PBO verificada. Confirmar con el soporte de partners si aplica a 2GP.
2. **Push upgrades.** Confirmar si requieren partnership o revisión de seguridad. Era la razón principal para hacer el paquete administrado.
3. **Token en custom setting.** Ya empaquetado, `Veleiro_Config__c` puede pasar a `Protected`, que en un managed package **sí está permitido**. Eso cierra el hueco de que cualquier usuario con API pueda leer el token.
4. **Clientes actuales.** Codeart, FastCloud y Veleiro Main usan la versión sin namespace y **no se actualizan solas**: migrarlas implica instalar el paquete, trasladar vínculos y configuración, y luego quitar lo viejo.
