# Financeiro Pro - instalacao local no Windows

Este modo transforma o computador em servidor local do Financeiro Pro e salva os dados somente nesse computador.

O instalador cria automaticamente:

- o arquivo de configuracao local;
- o banco local `data.local.json`;
- o usuario inicial de acesso;
- os atalhos da Area de Trabalho;
- a inicializacao junto com o Windows.

## Como instalar com o instalador

1. Instale o Node.js LTS no computador, se ainda nao tiver.
2. Copie o arquivo `Financeiro-Pro-Instalador.exe` para o computador.
3. De dois cliques no arquivo e aguarde a instalacao terminar.
4. Abra pelo atalho `Financeiro Pro` criado na Area de Trabalho.

O instalador mantem a tela aberta no final. Se aparecer algum erro, copie a mensagem ou tire uma foto.

## Como instalar manualmente

1. Instale o Node.js LTS no computador, se ainda nao tiver.
2. Copie a pasta `financeiro-pro-app` para o computador.
3. Clique com o botao direito no PowerShell e abra como usuario normal.
4. Rode:

```powershell
cd "C:\caminho\da\pasta\financeiro-pro-app"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-local-server.ps1
```

## Como usar

Depois da instalacao, abra pelo atalho `Financeiro Pro` na Area de Trabalho.

Login inicial:

```text
Usuario: admin.financeiro
Senha: FinanceiroLocal@2026
```

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

## Onde os dados ficam

Os dados ficam no arquivo:

```text
data.local.json
```

Cada computador instalado tera o proprio arquivo e os proprios dados. Sem `DATABASE_URL`, nada e enviado para Neon, Render ou Vercel.

## Como gerar os arquivos de instalacao

Para gerar um novo instalador `.exe` na Area de Trabalho:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

Para gerar somente o ZIP:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-local-installer-package.ps1
```
