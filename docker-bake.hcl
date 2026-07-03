# =============================================================================
# a-blog cms Docker Images — ビルド定義（単一の真実の源）
#
# 対応PHPバージョンを増減するときは PHP_VERSIONS を編集するだけでよい。
# CI もローカルもこの1ファイルを参照する。
#
#   ローカルで全バージョンをビルド（ホストのアーキのみ）:
#     docker buildx bake
#
#   単一バージョンをローカルに load して試す（Apple Silicon 例）:
#     docker buildx bake acms-dev-8-3 --set "*.platform=linux/arm64" --load
#
#   マルチアーキで push（CI 相当）:
#     docker buildx bake --push
#
#   展開結果（ターゲット・タグ）の確認:
#     docker buildx bake --print
# =============================================================================

# 公開先の Docker Hub 名前空間。実際に作成する組織名に合わせること
# （appleple が取得済みかは要確認。異なる場合はこの1行を変更）。
variable "REGISTRY" {
  default = "appleple"
}

# このリポジトリが作るのは「実行環境のみ（a-blog cms 非同梱）」のイメージ。
variable "IMAGE_NAME" {
  default = "acms-dev"
}

# latest タグを付与するバージョン
variable "PHP_LATEST" {
  default = "8.5"
}

# PR プレビュー用のタグ接尾辞（CI が -<PR番号> を渡す想定。通常は空）
variable "PR_TAG" {
  default = ""
}

# ビルド対象のマルチアーキ。CI では push と併せてこのまま使う。
variable "PLATFORMS" {
  default = ["linux/amd64", "linux/arm64"]
}

# ---- ここがバージョン一覧の唯一の定義箇所 ----
variable "PHP_VERSIONS" {
  default = ["7.2", "7.3", "7.4", "8.0", "8.1", "8.2", "8.3", "8.4", "8.5"]
}

group "default" {
  targets = ["acms-dev"]
}

target "acms-dev" {
  name       = "acms-dev-${replace(php, ".", "-")}"
  context    = "."
  dockerfile = "Dockerfile"

  matrix = {
    php = PHP_VERSIONS
  }

  args = {
    PHP_VERSION = php
  }

  platforms = PLATFORMS

  tags = concat(
    ["${REGISTRY}/${IMAGE_NAME}:${php}${PR_TAG}"],
    php == PHP_LATEST ? ["${REGISTRY}/${IMAGE_NAME}:latest${PR_TAG}"] : []
  )

  labels = {
    "org.opencontainers.image.title"       = "a-blog cms dev runtime (PHP ${php})"
    "org.opencontainers.image.source"      = "https://github.com/appleple/docker-acms"
    "org.opencontainers.image.description" = "Apache + PHP ${php} runtime for a-blog cms development (a-blog cms is NOT bundled; mount your project)"
  }
}
