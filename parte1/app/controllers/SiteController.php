<?php

declare(strict_types=1);

namespace app\controllers;

use Yii;
use yii\web\Controller;

/** Exposes a simple database connectivity check for the assessment environment. */
final class SiteController extends Controller
{
    /**
     * Returns the number of seeded contracts when the database is reachable.
     *
     * @return array{status: 'ok', database: 'connected', contracts: int} The JSON response body.
     */
    public function actionIndex(): array
    {
        $contracts = (int) Yii::$app
            ->db
            ->createCommand('SELECT COUNT(*) FROM dbo.contratos')
            ->queryScalar();

        return [
            'status' => 'ok',
            'database' => 'connected',
            'contracts' => $contracts,
        ];
    }
}
