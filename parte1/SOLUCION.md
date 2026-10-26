# Solución — API de recepción de lecturas

## Ejecución

Desde `parte1/`, inicia la base de datos y la aplicación:

```bash
docker compose up -d db db-init
docker compose build app
docker compose run --rm --no-deps app composer install --no-interaction --prefer-dist
docker compose up -d app
```

La API queda disponible en `http://localhost:8000`.

En una clonación limpia, `vendor/` no está versionado. Es necesario ejecutar `composer install` antes de arrancar la aplicación. El arranque se ha comprobado desde un checkout limpio con este procedimiento.

El servidor PHP integrado se inicia con cuatro workers para permitir comprobar reintentos concurrentes en este entorno de evaluación. Esta configuración es solo para desarrollo y pruebas; el servidor integrado de PHP no se recomienda para producción. La aplicación arranca con `YII_DEBUG=false` para no exponer trazas técnicas en las respuestas.

## Endpoint

`POST /lecturas`

Envía un cuerpo JSON con estos campos:

| Campo | Tipo | Descripción |
|---|---|---|
| `cups` | string | CUPS del punto de suministro |
| `fecha_lectura` | string | Fecha de lectura con formato `YYYY-MM-DD` |
| `lectura_kwh` | integer | Valor acumulado del contador, en kWh |
| `tipo` | string | `real` o `estimada` |

Ejemplo:

```bash
curl -i -X POST http://localhost:8000/lecturas \
  -H 'Content-Type: application/json' \
  -d '{"cups":"ES0904998698797309NB","fecha_lectura":"2026-10-26","lectura_kwh":10900,"tipo":"real"}'
```

Una lectura nueva responde `201 Created`:

```json
{
  "status": "created",
  "message": "Lectura guardada."
}
```

## Respuestas principales

- `400 Bad Request`: campos inválidos, fecha incorrecta o tipo de lectura no admitido.
- `404 Not Found`: no existe ningún contrato para el CUPS.
- `409 Conflict`: ya existe una lectura diferente para ese contrato y fecha.
- `422 Unprocessable Entity`: contrato dado de baja, fecha fuera de vigencia, lectura futura o valor superior a la capacidad del contador.
- `500 Internal Server Error`: fallo inesperado al guardar la lectura.

## Decisiones

- La lectura se asocia al contrato que corresponde al CUPS **y a la fecha**. Esto permite distinguir contratos sucesivos del mismo punto de suministro.
- Se rechazan los contratos con estado `baja`, incluso si la fecha está dentro de la vigencia histórica, y las fechas fuera de vigencia. Las fechas de alta y baja se tratan como inclusivas.
- Se rechazan fechas futuras. La fecha de recepción se guarda en UTC.
- `lectura_kwh` es un valor acumulado entero. Se valida que no supere el máximo indicado por `digitos_contador`.
- Un reintento idéntico para el mismo contrato y fecha responde `200 OK` y no inserta otra fila. Si cambia el valor o el tipo, responde `409 Conflict`; la API no sustituye una lectura existente.
- La comprobación y el alta se realizan en una transacción serializable, con bloqueos sobre la búsqueda de lecturas. Se comprobó con diez peticiones simultáneas idénticas: una respondió `201`, nueve respondieron `200` y quedó una sola fila.
- Los datos iniciales ya contienen un duplicado exacto: las filas 121 y 137 comparten contrato, fecha, valor y tipo; solo cambia la fecha de recepción. La solución conserva los datos y no crea una restricción única que impida cargar el seed. La idempotencia verificada aplica a las escrituras realizadas por este endpoint; otros procesos que escriban directamente en la tabla deben aplicar una protección equivalente.
- Esta versión no implementa autenticación, importación por lotes ni regularización de lecturas estimadas. Se pueden añadir cuando se definan los requisitos de integración y las reglas de negocio correspondientes.

## Comprobaciones realizadas

- Lectura válida: `201 Created`.
- Reintento idéntico: `200 OK`, sin duplicar la fila.
- Diez reintentos simultáneos idénticos: una respuesta `201`, nueve respuestas `200` y una fila persistida.
- Mismo contrato y fecha con distinto valor: `409 Conflict`.
- Contrato dado de baja: `422 Unprocessable Entity`.
- Fecha fuera de vigencia: `422 Unprocessable Entity`.
- Fecha futura: `422 Unprocessable Entity`.
- CUPS desconocido: `404 Not Found`.
- Lectura superior a la capacidad del contador: `422 Unprocessable Entity`.
- Tipo de lectura no admitido: `400 Bad Request`.
- JSON malformado: `400 Bad Request` con el formato de error de la API y sin detalles internos.
- Diez peticiones simultáneas con varios workers: una respuesta `201`, nueve respuestas `200` y una fila persistida.
