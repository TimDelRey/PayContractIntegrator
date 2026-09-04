# Dev-план: генератор интеграций платёжных провайдеров

## 1. Цель и границы

Создать детерминированный Ruby CLI, который принимает `provider_api.yaml`, имя провайдера и обязательный versioned `integration_mapping.yml`, а за один запуск создаёт:

- `output/<provider>_service.rb` по контракту `Provider::BaseService`;
- `output/INTEGRATION.md` с настройкой, методами и mappings;
- `output/fixtures.json` с синтетическими запросами, ответами и callbacks.

Старая задача роутинга больше не является источником требований. Старые routing contract tests удалены и заменены переходным suite новой задачи.

OpenAPI задаёт транспортный контракт, но обычно не задаёт платёжную семантику. V1 получает роли операций, mappings, денежные единицы и правила подписи только из versioned `integration_mapping.yml` или поддерживаемых `x-space-payments-*` extensions; inference из имён и описаний запрещён. Точный объём поддержки OpenAPI 3.0.x/3.1.x фиксирует support matrix в разделе 3.7. Всё остальное даёт structured diagnostic.

До contract freeze нужно сверить реальный `provider_api.yaml` и `Provider::BaseService`. При отсутствии host-контракта используется executable `ProviderAdapterContract::V1`; версия записывается в manifest и показывается пользователю как warning. Исследования фиксируются со ссылками на официальную OpenAPI-спецификацию и документацию провайдера.

## 2. Разделение двух разработчиков

- **A — Spec Compiler:** safe loader, OpenAPI parser, local refs, provider-neutral IR, semantic validation и diagnostics.
- **B — Artifact Generator:** templates, service/docs/fixtures rendering, verification, atomic publication и CLI.

A не пишет templates/output. B не читает raw OpenAPI или mapping YAML, а получает immutable `IntegrationIR`. Оба контура тестируются независимо через frozen IR fixtures и compiler doubles.

```text
provider_api.yaml + integration_mapping.yml
  -> [A: Safe Loaders -> Parser -> RefResolver -> Mapping Resolver -> IR Builder -> Validator]
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

### 3.3 Versioned mapping contract

`integration_mapping.yml` имеет `schema_version: "1.0"` и связывает JSON Pointer/operationId с ролями create/status/cancel/webhook, field mappings, required/null semantics, денежными units и целочисленным conversion/rounding, status/error/event maps, idempotency, config keys и signature scheme. Приоритет: mapping → поддерживаемое `x-space-payments-*` extension → diagnostic. Конфликт, отсутствующий/неиспользованный pointer или пропуск критичной семантики является error. Эвристика по operationId/path/summary/description запрещена. Схема mapping и enums замораживаются с IR contract.

### 3.4 Provider adapter и callback contract

До renderer фиксируется executable `ProviderAdapterContract::V1`: сигнатуры четырёх BaseService-методов, operation, credentials/config, HTTP client, success/failure, exceptions и status transitions. Fake host реализует контракт для generated harness.

Callback получает неизменённый `raw_body`, нормализованные headers и отдельно parsed payload. Signature IR фиксирует exact signed bytes/parts, algorithm, encoding, header, secret source и, если документировано, timestamp/replay policy. Проверка выполняется до использования payload с constant-time comparison. Если host не передаёт raw bytes/headers или подпись не описана, generation завершается error diagnostic.

### 3.5 Generator и artifacts

```ruby
artifact_set = IntegrationGenerator::Generator.new(
  templates: template_registry
).call(ir: compile_result.ir)

ArtifactSet = Data.define(:service, :guide, :fixtures, :manifest, :diagnostics)
```

Renderer не парсит YAML. Одинаковые IR, config и template version дают байт-в-байт одинаковый результат.

### 3.6 CLI, layout и publication

```bash
bin/integrate --spec provider_api.yaml --mapping integration_mapping.yml --provider novapay --lang ruby --output output
```

Exit codes: `0` success, `2` invalid input/spec, `3` unsupported/ambiguous, `4` generation/verification failure, `5` output conflict/publication failure. CLI показывает стадии, endpoints/auth/webhooks, warnings, fallbacks и итоговые пути.

По умолчанию создаётся flat layout из примера задачи: `output/novapay_service.rb`, `output/INTEGRATION.md`, `output/fixtures.json`. `--layout rails` помещает service в `output/app/services/provider/novapay_service.rb`; остальные файлы остаются в корне. Manifest содержит `service_install_path: app/services/provider/novapay_service.rb`, guide объясняет установку flat-файла, оба layout покрыты acceptance tests.

Артефакты сначала создаются и проверяются во временной директории, затем публикуются целиком. Existing output не перезаписывается без `--force`; при ошибке старый output не меняется.

### 3.7 OpenAPI V1 support matrix

| Область | Поддерживается | Error diagnostic |
|---|---|---|
| Версии | OpenAPI 3.0.x/3.1.x | Swagger 2.0/unknown |
| References | local `$ref`, bounds/cycles detection | remote/missing/cyclic refs |
| Schemas | object/array/scalars, required, enum, format, nullable 3.0/null union 3.1 | oneOf/anyOf/discriminator, ambiguous allOf, dynamic/recursive |
| Parameters | path/query/header/cookie, primitive/array, form/simple | deepObject/прочие styles |
| Bodies | однозначный `application/json` | multipart/binary/XML/ambiguous content |
| Servers | один literal HTTPS либо выбранный mapping | ambiguity/variables/unsafe scheme |
| Security | apiKey, Basic/Bearer, operation override | OAuth/OpenID/ambiguous alternatives |
| Notifications | callbacks 3.0/3.1, webhooks 3.1 с explicit mapping | dynamic expression/unknown signature |

`open_api_support.yml` — versioned registry; tests отдельно проверяют 3.0/3.1. README заявляет только эту матрицу.


## 4. Целевая структура и владение

```text
app/services/integration_generator/
  contracts.rb, errors.rb       # совместный freeze
  compiler.rb                   # A
  spec_loader.rb                # A
  open_api_parser.rb            # A
  local_ref_resolver.rb         # A
  mapping_loader.rb             # A
  mapping_resolver.rb           # A
  ir_builder.rb                 # A
  semantic_validator.rb         # A
  diagnostics.rb                # A
  provider_adapter_contract/v1.rb # совместный freeze
  open_api_support.yml          # совместный freeze
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
| Mapping loader/resolver | A | через Compiler contract | `mapping_loader_test.rb`, `mapping_resolver_test.rb` |
| Provider adapter v1 | совместно | generated harness | `provider_adapter_contract_test.rb` |
| IR builder/semantic validator | A | `01`, `02` | `ir_builder_test.rb`, `semantic_validator_test.rb` |
| Generator/ArtifactSet | B | `test/contracts/03_generator_contract_test.rb` | `generator_test.rb` |
| Service/security renderers | B | через Generator contract | `service_renderer_test.rb`, `generated_code_security_test.rb` |
| Guide/fixtures renderers | B | через Generator contract | `guide_renderer_test.rb`, `fixtures_renderer_test.rb` |
| Verifier/publisher | B | через Generator/CLI contracts | `artifact_verifier_test.rb`, `atomic_publisher_test.rb` |
| CLI и интеграция A→B | B + совместно | `test/contracts/04_cli_contract_test.rb` | `cli_test.rb`, `test/integration/generation_pipeline_test.rb` |

Contract tests должны зеленеть строго в порядке `01 → 02 → 03 → 04`. A использует frozen IR fixture для проверки Compiler output; B использует тот же fixture как input и не ждёт готовности parser. Изменение поля IR или сигнатуры требует одновременного обновления contracts, обоих затронутых тестовых doubles и согласования разработчиков.

## 5. Разработчик A — задачи и тесты

### A0. Contract freeze

Сверить input, BaseService, mapping schema, IR, diagnostics и unsupported policy. Зафиксировать adapter v1 и fake host, если BaseService недоступен. Использовать заменившие старый routing suite тесты: `01_ir_contract_test.rb`, `02_compiler_contract_test.rb`, `03_generator_contract_test.rb`, `04_cli_contract_test.rb`.

### A1. Safe loader

Реализовать `Psych.safe_load` для spec и mapping, запрет aliases/Ruby objects, отдельные size/nesting limits, понятные syntax/location errors.

**Тест:** `spec_loader_test.rb`: YAML/JSON-compatible input, malformed YAML, aliases, object tags, oversized/deep input.

### A2. Parser и local refs

Разобрать version, servers, paths/verbs, parameters, schemas, examples, security, callbacks/webhooks. Разрешать только local refs, находить missing refs и cycles.

**Тесты:** `open_api_parser_test.rb`, `local_ref_resolver_test.rb`.

### A3. Mapping resolver

Валидировать mapping schema, JSON Pointers, enums и полноту критичной семантики; применять приоритет mapping/extensions без эвристик, выявлять конфликты и неиспользованные правила.

**Тесты:** `mapping_loader_test.rb`, `mapping_resolver_test.rb` на version/pointer/conflict/complete/missing semantics.

### A4. IR builder

Нормализовать разные specs без provider-specific branches. Роли и доменные mappings берутся только из validated mapping/extensions; отсутствие либо неоднозначность является error.

**Тест:** `ir_builder_test.rb` на NovaPay-подобной и структурно другой спецификации.

### A5. Semantic validator

Проверить auth, base URL, required fields, money units, status/error maps, idempotency и webhook signature metadata. Errors/warnings содержат source paths и hints.

**Тест:** `semantic_validator_test.rb`: критичные пропуски, auth alternatives, optional fields и unsupported constructs.

**Готовность A:** contract tests 01–02 зелёные; B получает стабильный IR fixture и diagnostics catalog.

## 6. Разработчик B — задачи и тесты

### B0. Template contract

Зафиксировать manifest, template version, реальный BaseService либо adapter v1, callback raw-body contract, Ruby literal escaping и оба layout. Работать с fake IR от A.

### B1. Service renderer

Генерировать class/namespace, BASE_URL/config, auth headers, request builders, response parsing, `check_conditions`, `create_request`, `fetch_status`, `process_callback`, status/error maps. Недокументированные методы не генерируются.

**Тест:** `service_renderer_test.rb` плюс generated BaseService contract harness с fake client.

### B2. Безопасность generated code

Сохранить idempotency, безопасно экранировать Ruby literals, не вставлять secrets, передавать raw body/headers и генерировать signature verification exact bytes с constant-time comparison. Отсутствующий callback contract является generation error. Malicious names/content не становятся Ruby-кодом.

**Тест:** `generated_code_security_test.rb`.

### B3. Guide и fixtures

Оба файла строятся из того же IR. Guide содержит auth/config, endpoints, units, mappings, error actions, idempotency, webhook и warnings. Fixtures синтетические и покрывают success/error/status/callback.

**Тесты:** `guide_renderer_test.rb`, `fixtures_renderer_test.rb`; JSON parse и consistency с IR.

### B4. Verifier и atomic publisher

Проверить обязательные файлы, `ruby -c`, RuboCop, JSON, manifest/checksums и contract harness. При ошибке выполнить rollback без смешанного output.

**Тесты:** `artifact_verifier_test.rb`, `atomic_publisher_test.rb`.

### B5. CLI

Реализовать один запуск, обязательный `--mapping`, `--layout flat|rails`, `--help`, defaults, exit codes, `--force`, summary и diagnostics с mapping/adapter versions и install path.

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
| Явная платёжная семантика | MappingResolver | mapping/conflict/no-inference tests |
| BaseService/callback contract | Adapter + Renderer | fake-host/raw-body/signature tests |
| Layout и OpenAPI scope | CLI + Parser | layout/support-matrix tests |
| Разные спецификации | Compiler | две разные fixtures |
| Unsupported/ambiguity | Validator + CLI | diagnostic/exit-code tests |
| Guide + fixtures | renderers | golden/consistency tests |
| Один понятный запуск | CLI | pipeline test |
| Безопасный output | verifier/publisher | syntax/lint/security/rollback tests |

## 8. Интеграция и чекпоинты

1. Общий PR: contracts, mapping schema, adapter/fake host, support registry, diagnostics codes, две provider-neutral fixtures; удалить/заменить routing tests.
2. Параллельно: A компилирует spec в IR, B генерирует из frozen IR fixture.
3. Интеграция: Compiler подключается к Generator только через `IntegrationIR`.
4. Checkpoint 1: safe parse, endpoints/auth и diagnostics.
5. Checkpoint 2: IR, generated service, syntax и fake-client demo.
6. Checkpoint 3: полный CLI, три artifacts, другая spec, errors и rollback demo.

## 9. Definition of Done

- один CLI-запуск с versioned mapping создаёт три файла в выбранном layout;
- service соответствует фактическому BaseService и работает с fake client;
- при отсутствии BaseService executable adapter v1 и его warning/manifest version обязательны;
- auth, fields, units, statuses, errors, idempotency и webhook traceable к spec/config;
- ambiguity, mapping conflicts и adapter fallback видимы; inference платёжной семантики отсутствует;
- две разные specs проходят end-to-end;
- output детерминирован и публикуется атомарно;
- нет provider calls, secrets, proprietary или AI-компонентов;
- Minitest, generated harness, `ruby -c`, RuboCop, Brakeman и dependency audit зелёные.

## 10. Простая документация и запуск

README объясняет назначение, требования, `bin/setup`, одну команду генерации, spec/mapping inputs, flat/Rails outputs, install path, OpenAPI support matrix и adapter assumption, diagnostics/exit codes, `--force`, тесты и проверки:

```bash
bin/setup
bin/integrate --spec provider_api.yaml --mapping integration_mapping.yml --provider novapay --lang ruby
```

B проверяет README в чистом окружении; A независимо повторяет только документированные команды. Готово, когда новый разработчик без устных пояснений генерирует, проверяет и находит все артефакты.
