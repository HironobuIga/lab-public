# lab-public

Public experiments and verification code. One directory per experiment.
Some experiments accompany one of my technical articles; others stand on their own.

日本語版: [README.ja.md](README.ja.md)

- When an experiment accompanies an article, the code is frozen at publication time
  with an `article/<slug>` tag. Articles link to tags, so later changes to the code
  never diverge from what the article shows.
- The environment each experiment was verified on, and how to run it,
  are in each directory's README.
- This is verification code written for experiments and articles.
  It is not guaranteed to be production quality.

## Index

| Directory | Summary | Article |
| --------- | ------- | ------- |
| [strands-mcp-client-oauth](strands-mcp-client-oauth/) | What Strands Agents' built-in `MCPClient(auth=...)` does on the wire against a local AS + RS | [ja](https://iganin.dev/ja/articles/strands-mcp-client-oauth/) / [en](https://iganin.dev/en/articles/strands-mcp-client-oauth/) |
| [authzen-pdp-swap](authzen-pdp-swap/) | The same AuthZEN evaluation request against Keycloak and against OPA behind an adapter | [ja](https://iganin.dev/ja/articles/authzen-pdp-swap/) / [en](https://iganin.dev/en/articles/authzen-pdp-swap/) |

## License

[MIT](LICENSE)
