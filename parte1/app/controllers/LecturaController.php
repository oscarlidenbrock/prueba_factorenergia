<?php

declare(strict_types=1);

namespace app\controllers;

use DateTimeImmutable;
use Yii;
use yii\db\Transaction;
use yii\web\Controller;

final class LecturaController extends Controller
{
    public $enableCsrfValidation = false;

    public function actionCreate(): array
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

        if ($contract['estado'] !== 'activo') {
            return $this->error(422, 'contract_inactive', 'El contrato está dado de baja.');
        }

        $maximum = (10 ** (int) $contract['digitos_contador']) - 1;

        if ($reading > $maximum) {
            return $this->error(
                422,
                'reading_out_of_range',
                "La lectura supera el máximo del contador ({$maximum} kWh)."
            );
        }

        $transaction = $db->beginTransaction(Transaction::SERIALIZABLE);

        try {
            $existing = $db->createCommand(
                'SELECT lectura_kwh, tipo
                 FROM dbo.lecturas WITH (UPDLOCK, HOLDLOCK)
                 WHERE contrato_id = :contractId AND fecha_lectura = :date',
                [':contractId' => $contract['id'], ':date' => $date]
            )->queryAll();

            if ($existing !== []) {
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

    private function error(int $status, string $code, string $message): array
    {
        Yii::$app->response->statusCode = $status;

        return ['status' => 'error', 'code' => $code, 'message' => $message];
    }
}