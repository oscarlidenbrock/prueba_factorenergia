# Parte 1: API de recepción de lecturas

## Contexto

Las distribuidoras nos envían cada mes las lecturas de los contadores de nuestros clientes. Hasta ahora llegaban en ficheros. La primera distribuidora con la que vamos a cambiar de sistema quiere enviarlas a través de una API. Tu objetivo es construir una primera versión pequeña, útil y explicable de esa API.

## Datos disponibles

El `compose.yaml` levanta un SQL Server 2022 y carga automáticamente la base de datos `lecturas` (`db/init.sql`) con dos tablas:

- `contratos`: contratos de suministro, con su CUPS, titular, tarifa, estado, fechas de alta y baja y número de dígitos del contador.
- `lecturas`: lecturas recibidas hasta ahora.

Desde el contenedor `app`, la base de datos está disponible con estos datos:

| Parámetro | Valor |
|-----------|-------|
| Host | `db` |
| Puerto | `1433` |
| Database | `lecturas` |
| User | `sa` |
| Password | `Prueba.Tecnica.2026` |

Desde tu máquina, SQL Server escucha en `localhost:14331`.

El contenedor `app` ya incluye PHP 8.3, los drivers de SQL Server (`sqlsrv` y `pdo_sqlsrv`) y Composer. Este DSN de PDO funciona desde `app`:

```
sqlsrv:Server=db,1433;Database=lecturas;TrustServerCertificate=1
```

Para abrir una consola SQL:

```bash
docker compose exec db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Prueba.Tecnica.2026' -C -I -d lecturas
```

Puedes modificar el `Dockerfile` y el `compose.yaml` según necesites.

## Requisitos de negocio

1. La solución debe exponer una API REST. La petición incluirá, como mínimo, el CUPS, la fecha de la lectura, la lectura del contador (kWh) y si es real o estimada.
2. Los contratos dados de baja no aceptan lecturas, y tampoco se aceptan lecturas con fecha fuera de la vigencia del contrato. La respuesta debe dejar claro que la lectura no se ha guardado y por qué.
3. Si la distribuidora no recibe respuesta, reintenta el envío. Recibir la misma lectura más de una vez no debe generar duplicados.

El contrato exacto de la API, las validaciones adicionales, la estructura del código y el resto de decisiones de implementación quedan a tu elección.

## Framework

Nuestras aplicaciones usan principalmente **Yii2**, así que es la opción preferente. Si prefieres otro framework (Symfony, Laravel…) o PHP sin framework, puedes usarlo: explica el motivo en tu `SOLUCION.md`.

## Criterios de evaluación

- **Funcionalidad:** cumplimiento de las características solicitadas y funcionamiento de la solución.
- **Decisiones:** contrato de la API, validaciones, tratamiento de errores y reintentos, estructura del código y demás decisiones de implementación.

## Entregables

1. Código fuente y declaración de dependencias (`composer.json`).
2. Instrucciones para ejecutar la solución y un ejemplo de petición.
3. Una explicación breve de las decisiones principales.

Puedes incluir esta explicación en un `SOLUCION.md` o en el lugar que te resulte más claro.
