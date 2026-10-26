# Parte 2: Incidencia en la facturación

## Contexto

El 5 de octubre se lanzó la facturación de septiembre. Desde entonces, Atención al Cliente ha registrado varias reclamaciones: algunos clientes dicen que han recibido la factura dos veces y otros que el importe es mucho más alto de lo normal.

El responsable de Facturación te escribe:

> Necesito saber qué ha pasado, a cuántos clientes afecta y qué hacemos. Y que no vuelva a pasar el mes que viene.

## Datos disponibles

El `compose.yaml` levanta un SQL Server 2022 y carga automáticamente la base de datos `facturacion` (`db/init.sql`). Es una copia de producción con los datos de abril a septiembre de 2026:

| Tabla / objeto | Contenido |
|----------------|-----------|
| `clientes` | Clientes |
| `contratos` | Contratos de suministro: CUPS, tarifa, distribuidora, forma de pago, alta y baja |
| `tarifas`, `tarifas_precios` | Tarifas y su historial de precios |
| `lecturas` | Lecturas recibidas de las distribuidoras: periodo, lectura del contador, consumo del periodo, tipo (real o estimada) y fichero de origen |
| `facturas` | Facturas generadas |
| `log_procesos` | Registro de ejecuciones de los procesos automáticos |
| `reclamaciones` | Reclamaciones recibidas desde el 5 de octubre |
| `sp_facturar_periodo` | Procedimiento almacenado que genera las facturas de un mes |

En `logs/` tienes la salida de Jenkins del proceso de facturación mensual.

Para simplificar, los importes no incluyen impuestos: el total de una factura es el consumo por el precio del kWh más el término fijo mensual.

Conexión:

| Parámetro | Valor |
|-----------|-------|
| Host | `localhost` |
| Puerto | `14332` |
| Database | `facturacion` |
| User | `sa` |
| Password | `Prueba.Tecnica.2026` |

La primera vez, la carga de datos tarda unos segundos después de `docker compose up -d`. Sabrás que ha terminado cuando `docker compose logs db-init` muestre `Base de datos 'facturacion' cargada.`

Puedes usar tu cliente habitual (SSMS, DBeaver, VS Code…) o abrir una consola en el contenedor:

```bash
docker compose exec db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Prueba.Tecnica.2026' -C -I -d facturacion
```

## Tu tarea

Investiga la incidencia y propón cómo resolverla. Las consultas, el enfoque, la corrección y el formato de las recomendaciones quedan a tu elección.

Ejecutaremos tus scripts sobre una base de datos recién creada con `docker compose up`, igual que la tuya.

## Criterios de evaluación

- **Funcionalidad:** los scripts se ejecutan y el diagnóstico está respaldado por los datos.
- **Decisiones:** cómo investigas, el alcance que identificas, la seguridad de la corrección, la prevención y cómo lo explicas a negocio.

## Entregables

1. Los scripts SQL de diagnóstico, corrección y prevención.
2. Un informe breve para el responsable de Facturación: qué ha pasado, a quién afecta, qué propones hacer y qué decisiones quedan pendientes de negocio.
3. Una explicación breve de tus decisiones. Puede ir en el mismo informe.
