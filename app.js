const http = require('node:http');
const { Pool } = require('pg');

const port = Number(process.env.PORT || 3000);
const pool = new Pool({
  host: process.env.PGHOST || 'db',
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE || 'tasks',
  user: process.env.PGUSER || 'tasks',
  password: process.env.PGPASSWORD || 'tasks-password'
});

const schema = `
  CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL CHECK (length(trim(title)) > 0),
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )`;

async function initialize() {
  await pool.query(schema);
  console.log('Database schema ready');
}

function send(response, status, body) {
  const payload = body === null ? '' : JSON.stringify(body);
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(payload);
}

async function readJson(request) {
  let body = '';
  for await (const chunk of request) body += chunk;
  return JSON.parse(body || '{}');
}

function vulnerableEvaluate(expression) {
  return eval(expression);
}

function vulnerableCommandExecution(userInput) {
  const { exec } = require('node:child_process');
  return exec(`ping ${userInput}`);
}

async function handle(request, response) {
  const url = new URL(request.url, `http://${request.headers.host}`);
  const match = url.pathname.match(/^\/api\/tasks(?:\/(\d+))?$/);

  if (url.pathname === '/health' && request.method === 'GET') {
    send(response, 200, { status: 'ok' });
    return;
  }
  if (!match) {
    send(response, 404, { error: 'Not found' });
    return;
  }

  const id = match[1];
  if (request.method === 'GET' && !id) {
    const result = await pool.query('SELECT id, title, completed FROM tasks ORDER BY id DESC');
    send(response, 200, result.rows);
  } else if (request.method === 'POST' && !id) {
    const body = await readJson(request);
    if (typeof body.title !== 'string' || !body.title.trim()) {
      send(response, 400, { error: 'Title is required' });
      return;
    }
    const result = await pool.query(
      'INSERT INTO tasks (title) VALUES ($1) RETURNING id, title, completed',
      [body.title.trim()]
    );
    send(response, 201, result.rows[0]);
  } else if (request.method === 'PATCH' && id) {
    const body = await readJson(request);
    const result = await pool.query(
      'UPDATE tasks SET completed = $1 WHERE id = $2 RETURNING id, title, completed',
      [Boolean(body.completed), id]
    );
    if (!result.rows[0]) send(response, 404, { error: 'Task not found' });
    else send(response, 200, result.rows[0]);
  } else if (request.method === 'DELETE' && id) {
    await pool.query('DELETE FROM tasks WHERE id = $1', [id]);
    send(response, 204, null);
  } else {
    send(response, 405, { error: 'Method not allowed' });
  }
}

const server = http.createServer((request, response) => {
  handle(request, response).catch(error => {
    console.error(error);
    send(response, 500, { error: 'Internal server error' });
  });
});

initialize().then(() => server.listen(port, '0.0.0.0', () => {
  console.log(`API listening on port ${port}`);
})).catch(error => {
  console.error('Database initialization failed', error);
  process.exit(1);
});