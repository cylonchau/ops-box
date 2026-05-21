# 自用 Shell 运维小工具箱

自用的 Linux 运维与自动化小工具箱。

---

## 极速调用

* **列出所有可用脚本**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- -l
  ```
* **远程执行格式**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- <脚本名称> [参数...]
  ```

---

## init-linux

* **All**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux all
  ```
* **VPS**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux vps
  ```
* **Init**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux init
  ```
* **Pkg**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux pkg
  ```
* **Mirror**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux mirror
  ```
* **Security**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux security
  ```
* **Time**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux time
  ```
* **SSH**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux ssh
  ```
* **Optimize**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux optimize
  ```
* **Docker**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux docker
  ```
* **Disk**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux disk sdb /data xfs
  ```
* **Autodisk**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux autodisk /data
  ```
* **Expand**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux expand
  ```
* **History**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux history
  ```
* **Clean**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- init-linux clean
  ```

## expand

* **Disk-tune**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- expand disk-tune
  ```
* **Sys-tune**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- expand sys-tune
  ```

## xfs-format

* **Format & Mount**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- xfs-format /dev/sdb /data/xfsdir
  ```

## mongo

* **Install**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo install --role primary --data-dir /var/lib/mongodb/primary --multi-instance --mongodb-version 7.0

  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo install --role secondary --data-dir /var/lib/mongodb/secondary --multi-instance --mongodb-version 7.0

  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo install --role arbiter --data-dir /var/lib/mongodb/arbiter --multi-instance --mongodb-version 7.0
  ```
* **Init-replica**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo init-replica \
    --role primary \
    --primary-ip 192.168.8.12 \
    --secondary-ip 192.168.8.12 \
    --arbiter-ip 192.168.8.12 \
    --multi-instance
  ```
* **Config-auth**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo config-auth \
    --role primary \
    --primary-ip 192.168.8.12 \
    --secondary-ip 192.168.8.12 \
    --arbiter-ip 192.168.8.12 \
    --multi-instance
  ```
* **Stop / Clean**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo stop
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo clean
  ```

## redis-install

* **Single**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- redis-install -t single -p 6379 -v 7.2.4
  ```
* **Single-cluster**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- redis-install -t single-cluster -p 6379,6380,6381
  ```

## nacos

* **Docker Deploy**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- nacos -v 2.5.1 -p
  ```

## install-couchbase

* **Install & Init**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- install-couchbase install
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- install-couchbase init --listen-ip 192.168.1.10 --admin-user Administrator --admin-pass password123
  ```
* **Add Node**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- install-couchbase add --node-ip 192.168.1.10 --second-node-ip 192.168.1.11
  ```

## node-exporter

* **Install**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- node-exporter install
  ```
* **Uninstall**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- node-exporter uninstall
  ```

## mysql-exporter

* **Install**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mysql-exporter install -h localhost -P 3306 -u root -p root_pwd -m mon
  ```
* **Uninstall**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mysql-exporter uninstall
  ```

## redis-exporter

* **Install**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- redis-exporter install -a 127.0.0.1:6379 -w 9121
  ```
* **Update**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- redis-exporter update -v 1.56.0
  ```

## network-exporter

* **Install**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- network-exporter
  ```
* **Uninstall**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- network-exporter --uninstall
  ```

## promtail

* **Install**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- promtail -l http://loki.internal:3100
  ```
* **Low Resource**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- promtail -l http://loki.internal:3100 --low-resource
  ```

## jenkins_backup

* **Local**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- jenkins_backup --backup --source-path /var/lib/jenkins --dir /tmp/jenkins-backups
  ```
* **S3**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- jenkins_backup --backup --source-path /var/lib/jenkins --s3 --s3-url http://10.0.0.5:9000 --s3-ak admin_ak --s3-sk admin_sk --s3-bucket backup-center --s3-cleanup-local
  ```

## mongo_backup

* **Local**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo_backup --backup --host 127.0.0.1 --port 27017 --user admin --pwd pass --db mydb
  ```
* **S3**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- mongo_backup --backup --uri "mongodb://admin:pass@h1,h2/?replicaSet=rs0" --s3 --s3-url http://minio:9000 --s3-ak ak --s3-sk sk --s3-bucket mongodb-backups
  ```

## nacos_backup

* **S3 Backup**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- nacos_backup --backup --db-host localhost --db-user nacos --db-pwd nacos --db-name nacos_devtest --s3 --s3-url http://minio:9000 --s3-ak ak --s3-sk sk --s3-bucket nacos-bucket
  ```
* **S3 Restore**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- nacos_backup --restore myminio/nacos-bucket/nacos-db/nacos_db_latest.sql.gz --db-host localhost --db-user nacos --db-pwd nacos
  ```

## nginx_backup

* **Local**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- nginx_backup --backup --source-path /etc/nginx --dir /tmp/nginx-backups
  ```

## sg

* **Sync Rules**
  ```bash
  curl -sL https://raw.githubusercontent.com/hardng/op-scripts/main/main.sh | bash -s -- sg
  ```

## update_linode_fw.py

* **Sync Firewall**
  ```bash
  python3 scripts/update_linode_fw.py
  ```
