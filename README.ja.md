# lab-public

公開する検証コード置き場。1 ディレクトリが 1 つの検証に対応します。
記事に添えているものもあれば、検証単体で公開しているものもあります。

English: [README.md](README.md)

- 記事に添える検証は、記事公開時点の内容をタグ `article/<slug>` で固定しています。
  記事からのリンクはタグを指すので、その後の変更で記事と食い違うことはありません。
- 動作確認した環境・実行方法は各ディレクトリの README にあります。
- 検証・記事のために書いたコードです。そのまま本番利用できる品質を保証するものではありません。

## 一覧

| ディレクトリ | 概要 | 記事 |
| ------------ | ---- | ---- |
| [strands-mcp-client-oauth](strands-mcp-client-oauth/) | Strands Agents 内蔵の `MCPClient(auth=...)` がローカルの AS + RS に対して何を送るか | [ja](https://portfolio-site.iganin.workers.dev/ja/articles/strands-mcp-client-oauth/) / [en](https://portfolio-site.iganin.workers.dev/en/articles/strands-mcp-client-oauth/) |
| [authzen-pdp-swap](authzen-pdp-swap/) | 同じ AuthZEN の判断要求を Keycloak とアダプタ経由の OPA に投げて比べる | [ja](https://portfolio-site.iganin.workers.dev/ja/articles/authzen-pdp-swap/) / [en](https://portfolio-site.iganin.workers.dev/en/articles/authzen-pdp-swap/) |

## License

[MIT](LICENSE)
