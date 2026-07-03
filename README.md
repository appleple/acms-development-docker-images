# a-blog cms Development Docker Images

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
| `appleple/acms-dev:8.3` | PHP 8.3 + Apache |
| `appleple/acms-dev:8.4` | PHP 8.4 + Apache |
| `appleple/acms-dev:8.5` | PHP 8.5 + Apache（`latest` と同一）|
| `appleple/acms-dev:latest` | 最新版（現在 8.5）|

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
    restart: always
    volumes:
      - ./www:/var/www/html
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "80:80"
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

> `privileged: true` は不要です（entrypoint の処理は通常の root 権限で完結します）。
> HTTPS を使う場合は自己署名証明書の作成と `a2ensite default-ssl` の有効化が別途必要です
> （既定では `443` は公開しておらず、SSL 用の vhost も未設定です）。

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
  設定は [`config/pcov.ini`](config/pcov.ini) にありますが、これは**ビルド時にイメージへ焼き込まれる**ため、
  取得済みイメージに対してこのファイルを編集しても反映されません。対象を絞る場合はイメージを再ビルドするか、
  実行時に `-d` で上書きしてください:
  ```sh
  docker compose exec www php -d pcov.enabled=1 -d pcov.directory=/var/www/html vendor/bin/phpunit --coverage-text
  ```
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

- `build.yml` — `master` への push / 週次 / 手動実行で **Docker Hub (`appleple/acms-dev`) へマルチアーキ公開**（バージョン別 matrix 並列、provenance / SBOM 添付）。
- `pr-preview.yml` — Pull Request で **GHCR にプレビューイメージを公開**（`ghcr.io/<owner>/<repo>/acms-dev:<ver>-<PR番号>`、amd64・バージョン別 matrix）。フォークからの PR はビルド検証のみ。
- `pr-cleanup.yml` — PR クローズ時に GHCR のプレビュータグ（`-<PR番号>`）を削除。
- `lint.yml` — `actionlint` によるワークフロー静的検査。

公開には Secrets（`DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`）が必要です。
PR プレビューのクリーンアップには別途 `GHCR_DELETE_TOKEN`（`delete:packages` / `read:packages` 権限の PAT）が必要です。
未設定の場合、`pr-cleanup.yml` は削除をスキップし警告を出すだけで失敗はしません。
Actions は commit SHA でピン留めし、`dependabot` が更新 PR を出します。

## 可用性について

`HEALTHCHECK` は Apache への接続可否を検知しますが、**Docker 単体では `unhealthy` を理由に
コンテナを自動再起動しません**（`restart` ポリシーはプロセス終了時のみ発火します）。
本イメージは Apache をコンテナの PID1 として起動するため、Apache がクラッシュすると
コンテナ自体が終了します。`docker run --restart=always` や compose の `restart: always` を
指定していれば、その時点で正しく自動復旧します。
