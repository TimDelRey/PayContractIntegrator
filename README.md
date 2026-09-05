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
- `examples.json`;
- внутренний manifest с версиями и SHA-256.
