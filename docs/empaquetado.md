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

## Historial de versiones

| Versión | Id de suscriptor | Cobertura | Estado |
|---|---|---|---|
| 1.0.0.1 | `04tPe0000010onRIAQ` | 93% | Beta (sin promover) · instalada y verificada en scratch |

## Pendientes antes de entregar a un cliente en producción

1. **Verified Partner Business Org.** La pantalla de Package Manager avisa: para que los suscriptores instalen en **producción**, la org debe estar vinculada a una PBO verificada. Confirmar con el soporte de partners si aplica a 2GP.
2. **Push upgrades.** Confirmar si requieren partnership o revisión de seguridad. Era la razón principal para hacer el paquete administrado.
3. **Token en custom setting.** Ya empaquetado, `Veleiro_Config__c` puede pasar a `Protected`, que en un managed package **sí está permitido**. Eso cierra el hueco de que cualquier usuario con API pueda leer el token.
4. **Clientes actuales.** Codeart, FastCloud y Veleiro Main usan la versión sin namespace y **no se actualizan solas**: migrarlas implica instalar el paquete, trasladar vínculos y configuración, y luego quitar lo viejo.
