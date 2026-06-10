# Financeiro Pro

Aplicativo financeiro pronto para publicar no Render usando banco Neon.

## Variaveis no Render

- `DATABASE_URL`: connection string do Neon
- `JWT_SECRET`: texto secreto grande para login
- `ADMIN_USER`: usuario admin inicial
- `ADMIN_PASSWORD`: senha admin inicial

## Rodar localmente

```bash
npm install
npm start
```

Sem `DATABASE_URL`, o app usa `data.local.json` apenas para teste local.
