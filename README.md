# PayContractIntegrator

Ruby CLI генерирует интеграционные сервисы платёжных провайдеров из provider-neutral `IntegrationIR`.
Проект использует Ruby из `.ruby-version` и не зависит от веб-фреймворка, базы данных или внешнего сервиса.

## Подготовка

```bash
bin/setup
```

## Pipeline

`bin/integrate` запускает `MainWorker` с двумя независимыми этапами:

1. parsing — читает CLI/spec/mapping и возвращает immutable IR;
2. generation — создаёт, проверяет и атомарно публикует артефакты.

Parsing реализуется отдельно. Второй этап доступен как `Generator::Runner` и принимает объект с `ir`, `output` и `force`.

Generation использует закрытый `HandlerFactory` и Template Method `BaseHandler`. Результат содержит:

- `<provider>_service.rb` — дочерний класс `Provider::BaseService`;
- `INTEGRATION.md`;
- `fixtures.json`;
- внутренний manifest с версиями и SHA-256.

## Соответствие критериям кейса (черновик)

Таблица связывает разбалловку из брифа с местом в коде — чтобы ревью и оценка шли быстрее.
Это черновик: ссылки на файлы/классы, без номеров строк (чтобы не устаревало при рефакторинге).
Актуализировать перед чекпоинтом/защитой.

| Критерий | Баллы | Где в коде | Комментарий |
|---|---|---|---|
| **1. Корректность разбора API-спецификации** | 20 | | |
| — методы, параметры запросов/ответов | 8 | `lib/integration_generator/open_api_parser.rb` | версия, servers, paths/verbs, parameters, responses |
| — авторизация, статусы операций, ошибки | 7 | `lib/integration_generator/auth_resolver.rb`, `status_error_resolver.rb` | auth-схемы, status_map/error_map |
| — webhook и другие условия взаимодействия | 5 | `lib/integration_generator/webhook_resolver.rb` | подпись, event_map |
| **2. Генерация интеграционного сервиса** | 25 | | |
| — формирование и отправка запросов | 10 | `lib/generator/handlers/ruby_service_handler.rb`, `field_renderer.rb` | `create_request`, payload строится из `platform_source` |
| — обработка ответов, статусов, ошибок | 8 | `ruby_service_handler.rb` (`render_status`, `normalize_response`) | `STATUS_MAP`/`ERROR_MAP` |
| — входящие уведомления, настройка подключения | 7 | `ruby_service_handler.rb` (`render_callback`, `verify_webhook_signature!`) | ENV-конфиг, HMAC constant-time compare |
| **3. Корректность преобразования данных** | 15 | | |
| — сопоставление полей запросов/ответов/статусов | 8 | `lib/generator/contracts.rb` (`FieldIR#platform_source`), `lib/integration_generator/platform_field_resolver.rb` | id/amount/payout_requisite, requisite_container |
| — форматы, обязательные/необязательные поля | 7 | `lib/integration_generator/field_resolver.rb`, `lib/generator/platform_source_validator.rb` | required/required_if/nullable |
| **4. Универсальность решения** | 15 | | |
| — работает с разными спеками | 7 | `test/fixtures/integration_generator/providers/*.yaml`, `lib/integration_generator/semantic_resolver.rb` | NovaPay/SumUp/Adyen/PayPal-фикстуры |
| — логика не привязана к провайдеру | 5 | `test/services/integration_generator/generator_robustness_test.rb` | тест на отсутствие имён провайдеров в generation-коде |
| — новые правила / необрабатываемые элементы | 3 | `integration_mapping.yml` overrides (`required_if`, `platform_source`), `Generator::Diagnostic` | mapping — explicit escape hatch, не хардкод в коде |
| **5. Понятность использования и демонстрации** | 15 | | |
| — понятный однокомандный процесс | 6 | `bin/integrate`, `lib/generator/cli.rb` | один вызов, стабильные exit codes 0/2/3/4/5 |
| — настройка, авторизация, использование | 5 | `lib/generator/handlers/guide_handler.rb` → `INTEGRATION.md` | auth, config, mappings, webhook |
| — понятные результат и ошибки | 4 | `lib/generator/contracts.rb` (`Diagnostic`), `cli.rb` (`format_diagnostic`) | severity/code/source_path/hint |
| **6. Качество технической реализации** | 10 | | |
| — структура и разделение компонентов | 6 | `lib/integration_generator/` (Spec Compiler) vs `lib/generator/` (Artifact Generator) | см. `dev_plan.md` §2 |
| — обработка ошибок парсинга и генерации | 4 | `lib/integration_generator/errors.rb` (`SpecError`), `lib/generator/generation_error.rb`, `publication_error.rb` | единая иерархия ошибок на каждом этапе |
