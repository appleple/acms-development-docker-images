# a-blog cms Docker Images

a-blog cms 開発用の **実行環境イメージ（Apache + PHP、a-blog cms 非同梱）** です。
自分の a-blog cms プロジェクトをマウントして使います。
**すべての PHP バージョンを 1 つのブランチ（master）で管理**し、`docker buildx bake` でビルドします。

## 提供イメージ

| タグ | 内容 |
|------|------|
| `appleple/acms-dev:7.2` | PHP 7.2 + Apache |
| `appleple/acms-dev:7.3` | PHP 7.3 + Apache |
| `appleple/acms-dev:7.4` | PHP 7.4 + Apache |
| `appleple/acms-dev:8.0` | PHP 8.0 + Apache |
| `appleple/acms-dev:8.1` | PHP 8.1 + Apache |
| `appleple/acms-dev:8.2` | PHP 8.2 + Apache |
| `appleple/acms-dev:8.3` | PHP 8.3 + Apache（`latest` と同一）|
| `appleple/acms-dev:8.4` | PHP 8.4 + Apache |
| `appleple/acms-dev:8.5` | PHP 8.5 + Apache |
| `appleple/acms-dev:latest` | 最新安定版（現在 8.3）|

いずれも `linux/amd64` と `linux/arm64`（Apple Silicon）のマルチアーキ対応です。

## 使い方（docker compose）

```yaml
services:
  mysql:
    image: mysql:8.0
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: root

  www:
    image: appleple/acms-dev:8.3
    privileged: true
    volumes:
      - ./www:/var/www/html
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - mysql
    environment:
      APACHE_DOCUMENT_ROOT: /var/www/html
      # Xdebug を使う場合のみ true にする（既定は無効）
      # XDEBUG: "true"
      # Linux ホストでボリューム所有権を合わせたい場合（任意）
      # PUID: "1000"
      # PGID: "1000"
```

```sh
docker compose up
```

> `PUID`/`PGID` を渡すと Apache 実行ユーザ(www-data)の uid/gid をホストに合わせ、
> マウント先に生成されるファイルの所有権ずれ（主に Linux ホスト）を防げます。macOS/Windows では通常不要です。

## Xdebug

Xdebug はイメージに同梱されており、**専用イメージ（`-xdebug`）は不要**です。
環境変数 `XDEBUG=true` を渡すと起動時に有効化されます（同時に opcache は無効化）。
設定は [`config/xdebug.ini`](config/xdebug.ini) にあり、IDE はポート `9003` で待ち受ける想定です。

## テスト・カバレッジ（コア開発向け）

- **PCOV** を同梱しています（PHPUnit のカバレッジ取得用。Xdebug より高速）。
  既定は無効（`pcov.enabled=0`）で、常時のオーバーヘッドはありません。取得時のみ有効化します:
  ```sh
  docker compose exec www php -d pcov.enabled=1 vendor/bin/phpunit --coverage-text
  ```
  設定は [`config/pcov.ini`](config/pcov.ini)。対象を絞る場合は `pcov.directory` を指定。
- **exif** 拡張を同梱しています（EXIF Orientation を使う画像回転処理・テスト向け）。
- カバレッジは PCOV と Xdebug のどちらか一方のみ使用してください（併用は非対応）。
  ステップ実行が必要なときだけ `XDEBUG=true`、カバレッジは PCOV が推奨です。

> Node.js は同梱していません。テーマ／アセットのビルドはホストまたは別コンテナで行ってください。

## 開発（メンテナ向け）

対応バージョンや拡張を変更するときは、以下のソースだけを編集します（生成物はありません）。

- `Dockerfile` — 全バージョン共通。PHP バージョンは `ARG PHP_VERSION` で受け取る
- `docker-bake.hcl` — 対応バージョン一覧（`PHP_VERSIONS`）とタグ・アーキの定義
- `entrypoint.sh` / `config/*` — 起動処理・設定

```sh
# 展開されるターゲットとタグを確認
docker buildx bake --print

# 全バージョンをローカルビルド（ホストのアーキのみ）
docker buildx bake

# 単一バージョンを load して動作確認（Apple Silicon 例）
docker buildx bake acms-dev-8-3 --set "*.platform=linux/arm64" --load

# マルチアーキで公開（通常は CI が実行）
docker buildx bake --push
```

### CI（GitHub Actions）

- `build.yml` — `master` への push / 週次 / 手動実行で **Docker Hub (`appleple/acms-dev`) へマルチアーキ公開**（provenance / SBOM 添付）。
- `pr-preview.yml` — Pull Request で **GHCR にプレビューイメージを公開**（`ghcr.io/<owner>/docker-acms/acms-dev:<ver>-<PR番号>`）。フォークからの PR はビルド検証のみ。
- `lint.yml` — `actionlint` によるワークフロー静的検査。

公開には Secrets（`DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`）が必要です。
Actions は commit SHA でピン留めし、`dependabot` が更新 PR を出します。
