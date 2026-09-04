# PayContractIntegrator

Ruby CLI для генерации интеграций платёжных провайдеров из публичных OpenAPI-спецификаций.

Проект использует текущую версию Ruby из `.ruby-version` и не зависит от веб-фреймворка, базы данных или веб-сервера.

## Подготовка

```bash
bin/setup
```

## Запуск

```bash
bin/integrate --spec provider_api.yaml --mapping integration_mapping.yml --provider novapay --lang ruby
```

Главный worker выполняет два последовательных этапа: parsing и generation.

## Проверки

```bash
bundle exec rake test
bundle exec rubocop
bin/bundler-audit check
```
