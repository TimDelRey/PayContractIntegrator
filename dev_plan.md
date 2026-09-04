# Dev-план: генератор интеграций платёжных провайдеров

## 1. Цель и границы

Создать детерминированный Ruby CLI, который принимает `provider_api.yaml` и имя провайдера, а за один запуск создаёт:

- `output/<provider>_service.rb` по контракту `Provider::BaseService`;
- `output/INTEGRATION.md` с настройкой, методами и mappings;
- `output/fixtures.json` с синтетическими запросами, ответами и callbacks.

Старая задача роутинга больше не является источником требований. Старые routing contract tests удалены и заменены переходным suite новой задачи.

V1 поддерживает OpenAPI 3.0.x/3.1.x: servers, paths, parameters, requestBody, responses, components и local `$ref`, security, callbacks и webhooks. Версия читается из документа. Remote refs, OAuth flows, multipart/binary, XML, polymorphism и неоднозначные mappings не угадываются: пользователь получает structured diagnostic.

До contract freeze нужно сверить реальный `provider_api.yaml` и `Provider::BaseService`. При их отсутствии используется явно версионированный adapter contract, а допущение показывается пользователю. Исследования фиксируются со ссылками на официальную OpenAPI-спецификацию и документацию провайдера.

## 2. Разделение двух разработчиков

- **A — Spec Compiler:** safe loader, OpenAPI parser, local refs, provider-neutral IR, semantic validation и diagnostics.
- **B — Artifact Generator:** templates, service/docs/fixtures rendering, verification, atomic publication и CLI.

A не пишет templates/output. B не читает raw YAML, а получает immutable `IntegrationIR`. Оба контура тестируются независимо через frozen IR fixtures и compiler doubles.

```text
provider_api.yaml
  -> [A: Loader -> Parser -> RefResolver -> IR Builder -> Validator]
  -> IntegrationIR + Diagnostics
  -> [B: Renderer -> Verifier -> AtomicPublisher -> CLI]
  -> service.rb + INTEGRATION.md + fixtures.json
```

## 3. Контракты до параллельной работы

### 3.1 Compiler и diagnostics

```ruby
result = IntegrationGenerator::Compiler.new.call(
  source: yaml_string,
  source_name: "provider_api.yaml",
  provider_key: "novapay"
)

CompileResult = Data.define(:ir, :diagnostics)
Diagnostic = Data.define(:severity, :code, :message, :source_path, :hint)
```

При `error` diagnostic IR не передаётся в генерацию. Warning разрешает output только для необязательных сведений, не влияющих на деньги, auth, подпись, idempotency, статусы или ошибки.

### 3.2 Versioned IR

`IntegrationIR` содержит `schema_version`, provider key/class/env prefix, base URLs, auth alternatives, operations, callbacks/webhooks, status/error maps, money transformations, idempotency, config requirements и source metadata.

`OperationIR` содержит method/path, role, parameters по location, body schema, success/error responses и examples. `FieldIR` фиксирует source/generated names, required/nullability, type/format, unit conversion и default. Неизвестные значения не заменяются догадками. Идентификаторы проходят allowlist-нормализацию; `Float` для денег запрещён.

### 3.3 Generator и artifacts

```ruby
artifact_set = IntegrationGenerator::Generator.new(
  templates: template_registry
).call(ir: compile_result.ir)

ArtifactSet = Data.define(:service, :guide, :fixtures, :manifest, :diagnostics)
```

Renderer не парсит YAML. Одинаковые IR, config и template version дают байт-в-байт одинаковый результат.

### 3.4 CLI и publication

```bash
bin/integrate --spec provider_api.yaml --provider novapay --lang ruby --output output
```

Exit codes: `0` success, `2` invalid input/spec, `3` unsupported/ambiguous, `4` generation/verification failure, `5` output conflict/publication failure. CLI показывает стадии, endpoints/auth/webhooks, warnings, fallbacks и итоговые пути.

Артефакты сначала создаются и проверяются во временной директории, затем публикуются целиком. Existing output не перезаписывается без `--force`; при ошибке старый output не меняется.

## 4. Целевая структура и владение

```text
app/services/integration_generator/
  contracts.rb, errors.rb       # совместный freeze
  compiler.rb                   # A
  spec_loader.rb                # A
  open_api_parser.rb            # A
  local_ref_resolver.rb         # A
  ir_builder.rb                 # A
  semantic_validator.rb         # A
  diagnostics.rb                # A
  generator.rb                  # B
  template_registry.rb          # B
  renderers/                    # B
  artifact_verifier.rb          # B
  atomic_publisher.rb           # B
  cli.rb                        # B
templates/ruby/                 # B
bin/integrate                   # B
test/contracts/                # совместно
test/services/integration_generator/
test/integration/generation_pipeline_test.rb
```

## 4.1. Карта модулей, владельцев и тестов

| Контракт/модуль | Владелец | Уже написанный переходный тест | Модульный тест при реализации |
|---|---|---|---|
| IR, diagnostics, CompileResult | совместно | `test/contracts/01_ir_contract_test.rb` | `test/services/integration_generator/contracts_test.rb` |
| Compiler boundary | A | `test/contracts/02_compiler_contract_test.rb` | `compiler_test.rb` |
| Safe loader | A | через Compiler contract | `spec_loader_test.rb` |
| OpenAPI parser/local refs | A | через Compiler contract | `open_api_parser_test.rb`, `local_ref_resolver_test.rb` |
| IR builder/semantic validator | A | `01`, `02` | `ir_builder_test.rb`, `semantic_validator_test.rb` |
| Generator/ArtifactSet | B | `test/contracts/03_generator_contract_test.rb` | `generator_test.rb` |
| Service/security renderers | B | через Generator contract | `service_renderer_test.rb`, `generated_code_security_test.rb` |
| Guide/fixtures renderers | B | через Generator contract | `guide_renderer_test.rb`, `fixtures_renderer_test.rb` |
| Verifier/publisher | B | через Generator/CLI contracts | `artifact_verifier_test.rb`, `atomic_publisher_test.rb` |
| CLI и интеграция A→B | B + совместно | `test/contracts/04_cli_contract_test.rb` | `cli_test.rb`, `test/integration/generation_pipeline_test.rb` |

Contract tests должны зеленеть строго в порядке `01 → 02 → 03 → 04`. A использует frozen IR fixture для проверки Compiler output; B использует тот же fixture как input и не ждёт готовности parser. Изменение поля IR или сигнатуры требует одновременного обновления contracts, обоих затронутых тестовых doubles и согласования разработчиков.

## 5. Разработчик A — задачи и тесты

### A0. Contract freeze

Сверить input, BaseService, IR, diagnostics и unsupported policy. Использовать заменившие старый routing suite тесты: `01_ir_contract_test.rb`, `02_compiler_contract_test.rb`, `03_generator_contract_test.rb`, `04_cli_contract_test.rb`.

### A1. Safe loader

Реализовать `Psych.safe_load`, запрет aliases/Ruby objects, size/nesting limits, понятные syntax/location errors.

**Тест:** `spec_loader_test.rb`: YAML/JSON-compatible input, malformed YAML, aliases, object tags, oversized/deep input.

### A2. Parser и local refs

Разобрать version, servers, paths/verbs, parameters, schemas, examples, security, callbacks/webhooks. Разрешать только local refs, находить missing refs и cycles.

**Тесты:** `open_api_parser_test.rb`, `local_ref_resolver_test.rb`.

### A3. IR builder

Нормализовать разные specs без provider-specific branches. Роли create/status/cancel/webhook берутся из explicit extensions/config, затем однозначной documented semantics; неоднозначность является error.

**Тест:** `ir_builder_test.rb` на NovaPay-подобной и структурно другой спецификации.

### A4. Semantic validator

Проверить auth, base URL, required fields, money units, status/error maps, idempotency и webhook signature metadata. Errors/warnings содержат source paths и hints.

**Тест:** `semantic_validator_test.rb`: критичные пропуски, auth alternatives, optional fields и unsupported constructs.

**Готовность A:** contract tests 01–02 зелёные; B получает стабильный IR fixture и diagnostics catalog.

## 6. Разработчик B — задачи и тесты

### B0. Template contract

Зафиксировать manifest, template version, BaseService signatures и Ruby literal escaping. Работать с fake IR от A.

### B1. Service renderer

Генерировать class/namespace, BASE_URL/config, auth headers, request builders, response parsing, `check_conditions`, `create_request`, `fetch_status`, `process_callback`, status/error maps. Недокументированные методы не генерируются.

**Тест:** `service_renderer_test.rb` плюс generated BaseService contract harness с fake client.

### B2. Безопасность generated code

Сохранить idempotency, безопасно экранировать Ruby literals, не вставлять secrets, корректно генерировать signature verification hook и constant-time comparison. Malicious names/content не становятся Ruby-кодом.

**Тест:** `generated_code_security_test.rb`.

### B3. Guide и fixtures

Оба файла строятся из того же IR. Guide содержит auth/config, endpoints, units, mappings, error actions, idempotency, webhook и warnings. Fixtures синтетические и покрывают success/error/status/callback.

**Тесты:** `guide_renderer_test.rb`, `fixtures_renderer_test.rb`; JSON parse и consistency с IR.

### B4. Verifier и atomic publisher

Проверить обязательные файлы, `ruby -c`, RuboCop, JSON, manifest/checksums и contract harness. При ошибке выполнить rollback без смешанного output.

**Тесты:** `artifact_verifier_test.rb`, `atomic_publisher_test.rb`.

### B5. CLI

Реализовать один последовательный запуск, `--help`, defaults, exit codes, `--force`, summary и diagnostics.

**Тесты:** `cli_test.rb`, `test/integration/generation_pipeline_test.rb`.

**Готовность B:** contract tests 03–04 зелёные; три артефакта проходят verifier.

## 7. Матрица требований

| Требование idea_2 | Модуль | Проверка |
|---|---|---|
| Методы, параметры, ответы | Parser + IR | parser/IR tests |
| Auth, статусы, ошибки, webhook | Parser + Validator | semantic tests |
| BaseService service | ServiceRenderer | generated contract harness |
| Request/status/callback | ServiceRenderer | fake-client behavior tests |
| Поля, formats, units | IR + Renderer | transformation tests |
| Разные спецификации | Compiler | две разные fixtures |
| Unsupported/ambiguity | Validator + CLI | diagnostic/exit-code tests |
| Guide + fixtures | renderers | golden/consistency tests |
| Один понятный запуск | CLI | pipeline test |
| Безопасный output | verifier/publisher | syntax/lint/security/rollback tests |

## 8. Интеграция и чекпоинты

1. Общий PR: contracts, diagnostics codes, две provider-neutral fixtures; удалить/заменить routing tests.
2. Параллельно: A компилирует spec в IR, B генерирует из frozen IR fixture.
3. Интеграция: Compiler подключается к Generator только через `IntegrationIR`.
4. Checkpoint 1: safe parse, endpoints/auth и diagnostics.
5. Checkpoint 2: IR, generated service, syntax и fake-client demo.
6. Checkpoint 3: полный CLI, три artifacts, другая spec, errors и rollback demo.

## 9. Definition of Done

- один CLI-запуск создаёт три обязательных файла;
- service соответствует фактическому BaseService и работает с fake client;
- auth, fields, units, statuses, errors, idempotency и webhook traceable к spec/config;
- ambiguity и fallback видимы пользователю;
- две разные specs проходят end-to-end;
- output детерминирован и публикуется атомарно;
- нет provider calls, secrets, proprietary или AI-компонентов;
- Minitest, generated harness, `ruby -c`, RuboCop, Brakeman и dependency audit зелёные.

## 10. Простая документация и запуск

README объясняет назначение, требования, `bin/setup`, одну команду генерации, inputs/outputs, supported/unsupported OpenAPI features, diagnostics/exit codes, `--force`, тесты и проверки:

```bash
bin/setup
bin/integrate --spec provider_api.yaml --provider novapay --lang ruby
```

B проверяет README в чистом окружении; A независимо повторяет только документированные команды. Готово, когда новый разработчик без устных пояснений генерирует, проверяет и находит все артефакты.
