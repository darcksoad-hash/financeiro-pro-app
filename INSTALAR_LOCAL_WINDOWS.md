# Financeiro Pro - instalacao local no Windows

Este modo transforma o computador em servidor local do Financeiro Pro.

## Como instalar

1. Instale o Node.js LTS no computador, se ainda nao tiver.
2. Copie a pasta `financeiro-pro-app` para o computador.
3. Garanta que o arquivo `.env.vercel.local` exista com as variaveis do sistema.
4. Clique com o botao direito no PowerShell e abra como usuario normal.
5. Rode:

```powershell
cd "C:\caminho\da\pasta\financeiro-pro-app"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-local-server.ps1
```

## Como usar

Depois da instalacao, abra pelo atalho `Financeiro Pro` na Area de Trabalho.

Endereco local:

```text
http://127.0.0.1:3032/
```

Na mesma rede, outros computadores podem acessar pelo IP do servidor:

```text
http://IP-DO-COMPUTADOR:3032/
```

## Inicializacao automatica

O instalador cria atalhos na inicializacao do Windows para subir o servidor quando o computador ligar.

## Como parar

Use o atalho `Parar Servidor Financeiro Pro` na Area de Trabalho.

## Como remover os atalhos

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall-local-server.ps1
```

Isso remove os atalhos e para o servidor local. A pasta do sistema e os dados nao sao apagados.
