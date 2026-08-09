# Обоснование Terraform-конфигурации

## Выбор ресурсов

Конфигурация разворачивает MVP Data & Analytics Platform в Yandex Cloud. В состав инфраструктуры входят VPC `data-platform-network`, публичная и приватная подсети, четыре Security Group, сервисный аккаунт, Object Storage, Lockbox, Network Load Balancer, Managed PostgreSQL и восемь виртуальных машин.

Публичная подсеть используется только для bastion-host и внешнего Network Load Balancer. Bastion получает публичный IP и принимает SSH только с доверенного IP-адреса администратора. Все прикладные и data-компоненты находятся в приватной подсети: Portal UI, Portal Backend, Airflow, Dremio Coordinator, Dremio Executor, Spark Master и Spark Worker. Это исключает прямой доступ из интернета к Dremio, Airflow, Spark, backend и базе данных.

Network Load Balancer — единственная публичная точка входа в Portal UI. Он направляет HTTP-трафик на private IP Portal UI и выполняет health check `/health`. Portal UI обращается к Portal Backend, Backend — к Dremio и PostgreSQL. Airflow отправляет задачи в Spark Cluster; Spark записывает Data Products в Object Storage, а Dremio читает их из Lakehouse.

Security Groups разделены по ролям:

- `bastion-sg` разрешает SSH только из `admin_cidrs`;
- `portal-sg` принимает HTTP от NLB и SSH от bastion;
- `backend-sg` принимает API-трафик только от Portal UI и SSH от bastion;
- `data-sg` разрешает Backend обращаться к Dremio на порту `9047`, внутреннее взаимодействие data-компонентов и SSH от bastion;
- `database-sg` разрешает подключение к Managed PostgreSQL на порту `6432` только от Backend.

Такое разделение реализует принцип минимально необходимых сетевых прав и уменьшает поверхность атаки.

## Размеры виртуальных машин и дисков

Для учебного стенда выбраны минимально достаточные параметры. Они не предназначены для production-нагрузки в сотни ТБ, но позволяют проверить связи компонентов, доступы и автоматизацию.

| Компонент | vCPU / RAM | Boot disk |
| --- | --- | --- |
| Bastion | 2 / 2 GB | 10 GB SSD |
| Portal UI | 2 / 4 GB | 10 GB SSD |
| Portal Backend | 2 / 4 GB | 10 GB SSD |
| Airflow | 2 / 8 GB | 15 GB SSD |
| Spark Master | 4 / 16 GB | 25 GB SSD |
| Spark Worker (1) | 4 / 16 GB | 25 GB SSD |
| Dremio Coordinator | 4 / 16 GB | 30 GB SSD |
| Dremio Executor (1) | 4 / 16 GB | 30 GB SSD |

Суммарно boot-диски занимают 155 GB `network-ssd`, что укладывается в доступную учебную квоту 200 GB. Число Spark Worker и Dremio Executor задаётся переменными `spark_worker_count` и `dremio_executor_count`: при увеличении квот их можно масштабировать горизонтально без изменения архитектуры.

Managed PostgreSQL выбран для metadata DB портала: провайдер обслуживает резервное копирование, обновления и отказоустойчивость базы, а команда приложения применяет только миграции схемы через CI/CD. Object Storage выбран как Lakehouse, поскольку отделяет недорогое масштабируемое хранение Parquet/Iceberg-таблиц от compute. Включено versioning bucket, чтобы снизить риск безвозвратной потери объектов при ошибочной перезаписи.

## NAT и доступ в интернет

NAT включён только на bastion. Остальные VM не имеют публичных IP и доступны для администрирования через bastion. Это соответствует модели private-by-default. Для production-среды доступ private VM к внешним репозиториям и сервисам следует организовать через NAT Gateway или контролируемый egress proxy; в текущем учебном проекте разворачивается инфраструктурный слой, а установка приложений вынесена в CI/CD.

## Terraform и декларативный подход

Terraform описывает желаемое состояние инфраструктуры, а не последовательность ручных действий в консоли. В `main.tf` зафиксированы ресурсы и их связи; `variables.tf` содержит настраиваемые параметры; `terraform.tfvars` — значения учебной среды; `outputs.tf` — адреса и идентификаторы, нужные для последующего CI/CD. Terraform строит граф зависимостей: например, VM получают subnet, Security Group и service account, а NLB получает private IP Portal UI только после его создания.

Декларативный подход уменьшает риск расхождений между средами и ручных ошибок: изменения проходят через `terraform plan` до применения, а фактическое состояние фиксируется в `terraform.tfstate`. Повторный `terraform apply` сравнивает облачные ресурсы с конфигурацией и не создаёт дубликаты, если различий нет.

## Воспроизводимость и масштабируемость IaC

IaC делает инфраструктуру воспроизводимой: тот же набор `.tf` файлов и зафиксированная версия провайдера в `.terraform.lock.hcl` позволяют развернуть аналогичный стенд в другом folder или окружении, заменив только значения переменных. Конфигурация хранится вместе с архитектурной диаграммой в репозитории, поэтому изменения можно проверять в pull request и аудировать.

Масштабирование также становится параметризованным: для увеличения вычислительной мощности меняются размеры VM или количество worker/executor в `terraform.tfvars`; Terraform показывает последствия через plan и приводит инфраструктуру к новому состоянию. Разделение Object Storage и вычислительных кластеров позволяет масштабировать хранение и processing независимо друг от друга.

Секреты не записываются в `terraform.tfvars`: токен Terraform передаётся через переменную окружения `TF_VAR_yc_token`, а контейнер Yandex Lockbox создаётся Terraform. Значения прикладных секретов и настройки Dremio, Airflow, Spark, Portal UI/Backend должны добавляться защищённым CI/CD-процессом после provisioning инфраструктуры.
