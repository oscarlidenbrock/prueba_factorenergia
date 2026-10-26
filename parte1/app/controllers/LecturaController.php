<?php

declare(strict_types=1);

namespace app\controllers;

use DateTimeImmutable;
use Yii;
use yii\db\Transaction;
use yii\web\BadRequestHttpException;
use yii\web\Controller;

/** Receives cumulative meter readings and applies contract and retry rules. */
final class LecturaController extends Controller
{
    /** @var bool JSON clients do not use browser CSRF tokens. */
    public $enableCsrfValidation = false;

    /**
     * Handles POST /lecturas, mapping malformed JSON to invalid_json and other failures to internal_error.
     *
     * @return array<string, string> The JSON response body.
     */
    public function actionCreate(): array
    {
        try {
            return $this->createReading();
        } catch (BadRequestHttpException $exception) {
            return $this->error(400, 'invalid_json', 'El cuerpo de la petición debe contener un JSON válido.');
        } catch (\Throwable $exception) {
            Yii::error($exception->getMessage(), __METHOD__);

            return $this->error(500, 'internal_error', 'No se ha podido procesar la lectura.');
        }
    }

    /**
     * Validates the payload and stores a reading for the one effective, active contract.
     * An exact retry succeeds without changing the original row or reception time.
     *
     * @return array<string, string> The success or validation-error response body.
     */
    private function createReading(): array
    {
        $body = Yii::$app->request->bodyParams;

        $cups = $body['cups'] ?? null;
        $date = $body['fecha_lectura'] ?? null;
        $reading = $body['lectura_kwh'] ?? null;
        $type = $body['tipo'] ?? null;

        if (
            !is_string($cups) || trim($cups) === '' || strlen($cups) > 22
            || !is_string($date)
            || !is_int($reading) || $reading < 0
            || !in_array($type, ['real', 'estimada'], true)
        ) {
            return $this->error(400, 'invalid_request', 'Revisa los campos y sus tipos.');
        }

        $parsedDate = DateTimeImmutable::createFromFormat('!Y-m-d', $date);
        $dateErrors = DateTimeImmutable::getLastErrors();

        if (
            $parsedDate === false
            || ($dateErrors !== false && ($dateErrors['warning_count'] > 0 || $dateErrors['error_count'] > 0))
            || $parsedDate->format('Y-m-d') !== $date
        ) {
            return $this->error(400, 'invalid_date', 'La fecha debe tener formato YYYY-MM-DD y ser válida.');
        }

        if ($date > gmdate('Y-m-d')) {
            return $this->error(
                422,
                'future_reading',
                'La fecha de lectura no puede estar en el futuro.'
            );
        }

        $db = Yii::$app->db;
        $contracts = $db->createCommand(
            'SELECT id, estado, fecha_alta, fecha_baja, digitos_contador
             FROM dbo.contratos
             WHERE cups = :cups',
            [':cups' => trim($cups)]
        )->queryAll();

        if ($contracts === []) {
            return $this->error(404, 'contract_not_found', 'No existe un contrato para ese CUPS.');
        }

        // A CUPS can belong to successive contracts; both validity dates are inclusive.
        $validContracts = array_values(array_filter(
            $contracts,
            static fn (array $contract): bool =>
                $date >= $contract['fecha_alta']
                && ($contract['fecha_baja'] === null || $date <= $contract['fecha_baja'])
        ));

        if (count($validContracts) !== 1) {
            return $this->error(
                422,
                'contract_validity',
                count($validContracts) > 1
                    ? 'Hay varios contratos vigentes para ese CUPS en la fecha indicada.'
                    : 'La fecha de lectura queda fuera de la vigencia de cualquier contrato.'
            );
        }

        $contract = $validContracts[0];

        // A cancelled contract rejects even historical readings within its validity dates.
        if ($contract['estado'] !== 'activo') {
            return $this->error(422, 'contract_inactive', 'El contrato está dado de baja.');
        }

        // The reading is cumulative and must fit the contract's meter digit count.
        $maximum = (10 ** (int) $contract['digitos_contador']) - 1;

        if ($reading > $maximum) {
            return $this->error(
                422,
                'reading_out_of_range',
                "La lectura supera el máximo del contador ({$maximum} kWh)."
            );
        }

        // Keep the contract/date check and insert in one serializable, lock-protected transaction.
        $transaction = $db->beginTransaction(Transaction::SERIALIZABLE);

        try {
            $existing = $db->createCommand(
                'SELECT lectura_kwh, tipo
                 FROM dbo.lecturas WITH (UPDLOCK, HOLDLOCK)
                 WHERE contrato_id = :contractId AND fecha_lectura = :date',
                [':contractId' => $contract['id'], ':date' => $date]
            )->queryAll();

            if ($existing !== []) {
                // The seed contains duplicates; every existing row must match an exact retry.
                $sameReading = count(array_filter(
                        $existing,
                        static fn (array $row): bool =>
                            (int) $row['lectura_kwh'] === $reading && $row['tipo'] === $type
                    )) === count($existing);

                $transaction->commit();

                if ($sameReading) {
                    Yii::$app->response->statusCode = 200;

                    return [
                        'status' => 'duplicate',
                        'message' => 'La lectura ya estaba registrada.',
                    ];
                }

                return $this->error(
                    409,
                    'reading_conflict',
                    'Ya existe una lectura distinta para ese contrato y fecha.'
                );
            }

            // Timestamp reception on SQL Server to keep it in UTC.
            $db->createCommand(
                'INSERT INTO dbo.lecturas
                    (contrato_id, fecha_lectura, lectura_kwh, tipo, fecha_recepcion)
                 VALUES
                    (:contractId, :date, :reading, :type, SYSUTCDATETIME())',
                [
                    ':contractId' => $contract['id'],
                    ':date' => $date,
                    ':reading' => $reading,
                    ':type' => $type,
                ]
            )->execute();

            $transaction->commit();
            Yii::$app->response->statusCode = 201;

            return ['status' => 'created', 'message' => 'Lectura guardada.'];
        } catch (\Throwable $exception) {
            if ($transaction->isActive) {
                $transaction->rollBack();
            }

            Yii::error($exception->getMessage(), __METHOD__);

            return $this->error(500, 'internal_error', 'No se ha podido guardar la lectura.');
        }
    }

    /**
     * Sets the HTTP status and builds the shared validation/error response shape.
     *
     * @return array{status: 'error', code: string, message: string}
     */
    private function error(int $status, string $code, string $message): array
    {
        Yii::$app->response->statusCode = $status;

        return ['status' => 'error', 'code' => $code, 'message' => $message];
    }
}
