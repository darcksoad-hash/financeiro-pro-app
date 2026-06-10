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
const localDataFile = path.join(__dirname, 'data.local.json');

const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.DATABASE_URL.includes('localhost') ? false : { rejectUnauthorized: false }
    })
  : null;

app.use(express.json({ limit: '5mb' }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

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
      updated_at timestamptz not null default now()
    )
  `);
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

async function deleteUser(id) {
  if (!pool) {
    const data = await localRead();
    data.users = data.users.filter((u) => String(u.id) !== String(id) || u.role === 'admin');
    await localWrite(data);
    return;
  }
  await query("delete from app_users where id = $1 and role <> 'admin'", [id]);
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
    secure: process.env.NODE_ENV === 'production',
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
    return res.json({ clients: data.clients || [], loans: data.loans || [] });
  }
  const result = await query('select clients, loans from app_state where id = 1');
  res.json(result.rows[0] || { clients: [], loans: [] });
});

app.put('/api/state', requireAuth, async (req, res) => {
  const clients = Array.isArray(req.body.clients) ? req.body.clients : [];
  const loans = Array.isArray(req.body.loans) ? req.body.loans : [];
  if (!pool) {
    const data = await localRead();
    await localWrite({ ...data, clients, loans });
    return res.json({ ok: true });
  }
  await query('update app_state set clients = $1, loans = $2, updated_at = now() where id = 1', [
    JSON.stringify(clients),
    JSON.stringify(loans)
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

app.delete('/api/users/:id', requireAuth, requireAdmin, async (req, res) => {
  await deleteUser(req.params.id);
  res.json({ ok: true });
});

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

ensureDatabase()
  .then(() => app.listen(port, () => console.log(`Financeiro Pro running on port ${port}`)))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
