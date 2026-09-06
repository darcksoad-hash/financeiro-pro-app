import 'dotenv/config';
import express from 'express';
import cookieParser from 'cookie-parser';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { Pool } from 'pg';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
const port = process.env.PORT || 3000;
const jwtSecret = process.env.JWT_SECRET || 'local-development-secret-change-me';
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPassword = process.env.ADMIN_PASSWORD;
const localDataFile = process.env.LOCAL_DATA_FILE || path.join(__dirname, 'data.local.json');
const useSecureCookie = process.env.COOKIE_SECURE
  ? process.env.COOKIE_SECURE === 'true'
  : Boolean(process.env.DATABASE_URL && process.env.NODE_ENV === 'production');

const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.DATABASE_URL.includes('localhost') ? false : { rejectUnauthorized: false }
    })
  : null;

app.use(express.json({ limit: '5mb' }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

let databaseReady;

function getDatabaseReady() {
  if (!databaseReady) databaseReady = ensureDatabase();
  return databaseReady;
}

function signUser(user) {
  return jwt.sign({ id: user.id, username: user.username, role: user.role }, jwtSecret, { expiresIn: '7d' });
}

function publicUser(user) {
  return { id: user.id, username: user.username, role: user.role, createdAt: user.created_at || user.createdAt };
}

async function localRead() {
  try {
    return JSON.parse(await fs.readFile(localDataFile, 'utf8'));
  } catch {
    return { clients: [], loans: [], users: [] };
  }
}

async function localWrite(data) {
  await fs.writeFile(localDataFile, JSON.stringify(data, null, 2));
}

async function query(sql, params = []) {
  if (!pool) throw new Error('Database is not configured');
  return pool.query(sql, params);
}

async function ensureLocalAdmin() {
  const data = await localRead();
  const existing = data.users.find((u) => u.username === adminUser);
  if (existing && adminPassword) {
    existing.passwordHash = await bcrypt.hash(adminPassword, 12);
    existing.role = 'admin';
    await localWrite(data);
    return;
  }
  if (!existing) {
    data.users.push({
      id: Date.now().toString(),
      username: adminUser,
      passwordHash: await bcrypt.hash(adminPassword || 'admin12345', 12),
      role: 'admin',
      createdAt: new Date().toISOString()
    });
    await localWrite(data);
  }
}

async function ensureDatabase() {
  if (!pool) {
    await ensureLocalAdmin();
    return;
  }

  await query(`
    create table if not exists app_state (
      id integer primary key,
      clients jsonb not null default '[]'::jsonb,
      loans jsonb not null default '[]'::jsonb,
      history jsonb not null default '[]'::jsonb,
      updated_at timestamptz not null default now()
    )
  `);
  await query(`alter table app_state add column if not exists history jsonb not null default '[]'::jsonb`);
  await query(`
    create table if not exists app_users (
      id bigserial primary key,
      username text not null unique,
      password_hash text not null,
      role text not null default 'user',
      created_at timestamptz not null default now()
    )
  `);
  await query(`
    insert into app_state (id, clients, loans)
    values (1, '[]'::jsonb, '[]'::jsonb)
    on conflict (id) do nothing
  `);

  const existing = await query('select id from app_users where username = $1', [adminUser]);
  if (existing.rowCount === 0) {
    if (!adminPassword) {
      throw new Error('ADMIN_PASSWORD is required when DATABASE_URL is configured');
    }
    await query(
      'insert into app_users (username, password_hash, role) values ($1, $2, $3)',
      [adminUser, await bcrypt.hash(adminPassword, 12), 'admin']
    );
  } else if (process.env.SYNC_ADMIN_PASSWORD === 'true' && adminPassword && adminPassword.length >= 8) {
    await query(
      'update app_users set password_hash = $1, role = $2 where username = $3',
      [await bcrypt.hash(adminPassword, 12), 'admin', adminUser]
    );
  }
}

async function findUser(username) {
  if (!pool) {
    const data = await localRead();
    return data.users.find((u) => u.username === username) || null;
  }
  const result = await query('select * from app_users where username = $1', [username]);
  return result.rows[0] || null;
}

async function listUsers() {
  if (!pool) {
    const data = await localRead();
    return data.users.map(publicUser);
  }
  const result = await query('select id, username, role, created_at from app_users order by username');
  return result.rows.map(publicUser);
}

async function createUser(username, password, role = 'user') {
  const cleanRole = role === 'admin' ? 'admin' : 'user';
  const passwordHash = await bcrypt.hash(password, 12);
  if (!pool) {
    const data = await localRead();
    if (data.users.some((u) => u.username === username)) {
      const error = new Error('Usuario ja existe');
      error.status = 409;
      throw error;
    }
    data.users.push({ id: Date.now().toString(), username, passwordHash, role: cleanRole, createdAt: new Date().toISOString() });
    await localWrite(data);
    return;
  }
  await query('insert into app_users (username, password_hash, role) values ($1, $2, $3)', [username, passwordHash, cleanRole]);
}

async function updateUser(id, { username, password, role }) {
  const cleanRole = role === 'admin' ? 'admin' : 'user';
  if (!pool) {
    const data = await localRead();
    const user = data.users.find((u) => String(u.id) === String(id));
    if (!user) return;
    user.username = username;
    user.role = cleanRole;
    if (password) user.passwordHash = await bcrypt.hash(password, 12);
    await localWrite(data);
    return;
  }
  if (password) {
    await query(
      'update app_users set username = $1, role = $2, password_hash = $3 where id = $4',
      [username, cleanRole, await bcrypt.hash(password, 12), id]
    );
  } else {
    await query('update app_users set username = $1, role = $2 where id = $3', [username, cleanRole, id]);
  }
}

async function countAdmins(exceptId = null) {
  if (!pool) {
    const data = await localRead();
    return data.users.filter((u) => u.role === 'admin' && String(u.id) !== String(exceptId)).length;
  }
  const result = await query('select count(*)::int as total from app_users where role = $1 and id <> $2', [
    'admin',
    exceptId || 0
  ]);
  return result.rows[0]?.total || 0;
}

async function deleteUser(id, requesterId) {
  if (String(id) === String(requesterId)) {
    const error = new Error('Voce nao pode excluir o usuario logado');
    error.status = 400;
    throw error;
  }
  if (!pool) {
    const data = await localRead();
    const user = data.users.find((u) => String(u.id) === String(id));
    if (user?.role === 'admin' && (await countAdmins(id)) === 0) {
      const error = new Error('Mantenha pelo menos um admin');
      error.status = 400;
      throw error;
    }
    data.users = data.users.filter((u) => String(u.id) !== String(id));
    await localWrite(data);
    return;
  }
  const user = await query('select role from app_users where id = $1', [id]);
  if (user.rows[0]?.role === 'admin' && (await countAdmins(id)) === 0) {
    const error = new Error('Mantenha pelo menos um admin');
    error.status = 400;
    throw error;
  }
  await query('delete from app_users where id = $1', [id]);
}

async function changePassword(id, password) {
  const passwordHash = await bcrypt.hash(password, 12);
  if (!pool) {
    const data = await localRead();
    const user = data.users.find((u) => String(u.id) === String(id));
    if (user) user.passwordHash = passwordHash;
    await localWrite(data);
    return;
  }
  await query('update app_users set password_hash = $1 where id = $2', [passwordHash, id]);
}

function requireAuth(req, res, next) {
  try {
    req.user = jwt.verify(req.cookies.financeiro_token || '', jwtSecret);
    next();
  } catch {
    res.status(401).json({ error: 'Nao autenticado' });
  }
}

function requireAdmin(req, res, next) {
  if (req.user?.role !== 'admin') return res.status(403).json({ error: 'Acesso negado' });
  next();
}

app.use(async (_req, res, next) => {
  try {
    await getDatabaseReady();
    next();
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Erro ao preparar o banco de dados' });
  }
});

app.post('/api/login', async (req, res) => {
  const { username, password } = req.body || {};
  const user = username ? await findUser(username) : null;
  const hash = user?.password_hash || user?.passwordHash;
  if (!user || !hash || !(await bcrypt.compare(password || '', hash))) {
    return res.status(401).json({ error: 'Usuario ou senha invalidos' });
  }
  res.cookie('financeiro_token', signUser(user), {
    httpOnly: true,
    sameSite: 'lax',
    secure: useSecureCookie,
    maxAge: 7 * 24 * 60 * 60 * 1000
  });
  res.json({ user: publicUser(user) });
});

app.post('/api/logout', (_req, res) => {
  res.clearCookie('financeiro_token');
  res.json({ ok: true });
});

app.get('/api/session', requireAuth, (req, res) => {
  res.json({ user: req.user });
});

app.get('/api/state', requireAuth, async (_req, res) => {
  if (!pool) {
    const data = await localRead();
    return res.json({ clients: data.clients || [], loans: data.loans || [], history: data.history || [] });
  }
  const result = await query('select clients, loans, history from app_state where id = 1');
  res.json(result.rows[0] || { clients: [], loans: [], history: [] });
});

app.put('/api/state', requireAuth, async (req, res) => {
  const clients = Array.isArray(req.body.clients) ? req.body.clients : [];
  const loans = Array.isArray(req.body.loans) ? req.body.loans : [];
  const history = Array.isArray(req.body.history) ? req.body.history : [];
  if (!pool) {
    const data = await localRead();
    await localWrite({ ...data, clients, loans, history });
    return res.json({ ok: true });
  }
  await query('update app_state set clients = $1, loans = $2, history = $3, updated_at = now() where id = 1', [
    JSON.stringify(clients),
    JSON.stringify(loans),
    JSON.stringify(history)
  ]);
  res.json({ ok: true });
});

app.get('/api/users', requireAuth, requireAdmin, async (_req, res) => {
  res.json({ users: await listUsers() });
});

app.post('/api/users', requireAuth, requireAdmin, async (req, res) => {
  const username = String(req.body?.username || '').trim();
  const password = String(req.body?.password || '');
  const role = String(req.body?.role || 'user');
  if (!username || password.length < 8) {
    return res.status(400).json({ error: 'Informe usuario e senha com pelo menos 8 caracteres' });
  }
  try {
    await createUser(username, password, role);
    res.status(201).json({ ok: true });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || 'Erro ao criar usuario' });
  }
});

app.patch('/api/users/:id', requireAuth, requireAdmin, async (req, res) => {
  const username = String(req.body?.username || '').trim();
  const password = String(req.body?.password || '');
  const role = String(req.body?.role || 'user');
  if (!username) return res.status(400).json({ error: 'Informe o usuario' });
  if (password && password.length < 8) {
    return res.status(400).json({ error: 'Senha deve ter pelo menos 8 caracteres' });
  }
  try {
    await updateUser(req.params.id, { username, password: password || null, role });
    res.json({ ok: true });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || 'Erro ao atualizar usuario' });
  }
});

app.delete('/api/users/:id', requireAuth, requireAdmin, async (req, res) => {
  try {
    await deleteUser(req.params.id, req.user.id);
    res.json({ ok: true });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || 'Erro ao excluir usuario' });
  }
});

app.patch('/api/me/password', requireAuth, async (req, res) => {
  const password = String(req.body?.password || '');
  if (password.length < 8) {
    return res.status(400).json({ error: 'Senha deve ter pelo menos 8 caracteres' });
  }
  await changePassword(req.user.id, password);
  res.json({ ok: true });
});

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

if (!process.env.VERCEL) {
  getDatabaseReady()
    .then(() => app.listen(port, () => console.log(`Financeiro Pro running on port ${port}`)))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

export default app;
