const CAPABILITY_BYTES = 24;

export function generateCapability(cryptoSource = globalThis.crypto) {
  const bytes = new Uint8Array(CAPABILITY_BYTES);
  cryptoSource.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/u, '');
}

export function normalizeInviteUrl(raw, baseHref = globalThis.location.href) {
  const input = String(raw).trim();
  if (input.length === 0) return '';
  try {
    const base = new URL(baseHref);
    const invite = new URL(input, base);
    if (
      invite.origin !== base.origin
      || invite.username !== ''
      || invite.password !== ''
      || invite.hash !== ''
    ) return '';
    return `${invite.pathname}${invite.search}`;
  } catch {
    return '';
  }
}

export function buildWebSocketCollabUrl(role, room, peer, baseHref = globalThis.location.href) {
  const url = new URL('/collab', baseHref);
  url.search = new URLSearchParams({
    role: String(role),
    room: String(room),
    peer: String(peer),
    transport: 'websocket',
  }).toString();
  return url.href;
}

function node(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}

function labelledInput(id, labelText, attributes = {}) {
  const field = node('div', 'room-field');
  const label = node('label', 'room-label', labelText);
  label.htmlFor = id;
  const input = document.createElement('input');
  input.id = id;
  input.className = 'room-input';
  for (const [name, value] of Object.entries(attributes)) {
    if (name in input) input[name] = value;
    else input.setAttribute(name, value);
  }
  field.append(label, input);
  return { field, input };
}

function setCopyStatus(text, copied) {
  const status = document.getElementById('room-copy-status');
  const button = document.getElementById('room-copy-button');
  if (status) status.textContent = text;
  if (button) {
    button.textContent = copied ? 'Copied' : 'Copy invite link';
    button.dataset.copied = copied ? 'true' : 'false';
  }
}

async function copyInviteLink() {
  const input = document.getElementById('room-invite-output');
  if (!(input instanceof HTMLInputElement) || input.value === '') return;
  try {
    if (!navigator.clipboard?.writeText) throw new Error('clipboard unavailable');
    await navigator.clipboard.writeText(input.value);
    setCopyStatus('Invitation link copied.', true);
  } catch {
    input.focus();
    input.select();
    const copied = document.execCommand('copy');
    setCopyStatus(
      copied ? 'Invitation link copied.' : 'Copy failed. Select and copy the link manually.',
      copied,
    );
  }
}

function mountRoomChooser(onCreate, onJoin) {
  const app = document.getElementById('app');
  if (!app) return;

  const shell = node('main', 'room-shell');
  shell.setAttribute('aria-labelledby', 'room-title');

  const header = node('header', 'room-header');
  const title = node('h1', '', 'Share a typed spreadsheet');
  title.id = 'room-title';
  header.append(
    node('div', 'proof-kicker', 'WebSocket collaboration'),
    title,
    node('p', 'room-intro', 'Create a fresh room, or join one with an invitation link.'),
  );

  const actions = node('div', 'room-actions');
  const createSection = node('section', 'room-action room-action--create');
  createSection.setAttribute('aria-labelledby', 'room-create-title');
  const createTitle = node('h2', '', 'Create a room');
  createTitle.id = 'room-create-title';
  const createCopy = node('p', 'room-action-copy', 'Start a temporary two-person room and share its invitation link.');
  const createButton = node('button', 'primary-action room-main-action', 'Create room');
  createButton.type = 'button';
  createButton.id = 'room-create-button';
  createButton.addEventListener('click', () => onCreate());
  const createStatus = node('p', 'room-error');
  createStatus.id = 'room-create-status';
  createStatus.setAttribute('role', 'alert');
  createSection.append(createTitle, createCopy, createButton, createStatus);

  const created = node('div', 'room-created');
  created.id = 'room-created';
  created.hidden = true;
  const output = labelledInput('room-invite-output', 'Invitation link', { readOnly: true });
  output.input.setAttribute('aria-describedby', 'room-capability-note room-copy-status');
  const createdActions = node('div', 'room-created-actions');
  const copyButton = node('button', 'secondary-action', 'Copy invite link');
  copyButton.type = 'button';
  copyButton.id = 'room-copy-button';
  copyButton.addEventListener('click', copyInviteLink);
  const openButton = node('button', 'primary-action', 'Open room');
  openButton.type = 'button';
  openButton.id = 'room-open-button';
  openButton.addEventListener('click', () => {
    if (openButton.dataset.url) globalThis.location.assign(openButton.dataset.url);
  });
  createdActions.append(copyButton, openButton);
  const copyStatus = node('p', 'room-copy-status');
  copyStatus.id = 'room-copy-status';
  copyStatus.setAttribute('role', 'status');
  copyStatus.setAttribute('aria-live', 'polite');
  created.append(output.field, createdActions, copyStatus);
  createSection.append(created);

  const joinSection = node('section', 'room-action room-action--join');
  joinSection.setAttribute('aria-labelledby', 'room-join-title');
  const joinTitle = node('h2', '', 'Join a room');
  joinTitle.id = 'room-join-title';
  const joinCopy = node('p', 'room-action-copy', 'Paste an invitation from the person who created the room.');
  const joinForm = node('form', 'room-join-form');
  const joinField = labelledInput('room-join-input', 'Invitation link', {
    type: 'text',
    inputMode: 'url',
    required: true,
    autocomplete: 'off',
    spellcheck: false,
    placeholder: 'https://…/collab?role=join&…',
  });
  joinField.input.setAttribute('aria-describedby', 'room-join-error');
  const joinButton = node('button', 'secondary-action room-main-action', 'Join room');
  joinButton.type = 'submit';
  const joinError = node('p', 'room-error');
  joinError.id = 'room-join-error';
  joinError.setAttribute('role', 'alert');
  joinForm.addEventListener('submit', event => {
    event.preventDefault();
    joinError.textContent = '';
    joinField.input.removeAttribute('aria-invalid');
    onJoin(joinField.input.value);
  });
  joinForm.append(joinField.field, joinButton, joinError);
  joinSection.append(joinTitle, joinCopy, joinForm);
  actions.append(createSection, joinSection);

  const note = node('aside', 'room-capability-note');
  note.id = 'room-capability-note';
  note.setAttribute('role', 'note');
  note.append(
    node('strong', '', 'The invitation link is access.'),
    document.createTextNode(' Anyone with it can join this temporary room. Treat it like a password.'),
  );

  shell.append(header, actions, note);
  app.replaceChildren(shell);
}

function presentCreatedRoom(hostUrl, inviteUrl) {
  const created = document.getElementById('room-created');
  const output = document.getElementById('room-invite-output');
  const openButton = document.getElementById('room-open-button');
  const createButton = document.getElementById('room-create-button');
  const createStatus = document.getElementById('room-create-status');
  if (!(output instanceof HTMLInputElement) || !(openButton instanceof HTMLButtonElement)) return;
  output.value = String(inviteUrl);
  openButton.dataset.url = String(hostUrl);
  if (created) created.hidden = false;
  if (createButton) createButton.textContent = 'Create another room';
  if (createStatus) createStatus.textContent = '';
  setCopyStatus('Room ready. Copy the invitation, then open the room.', false);
}

function showRoomChooserError(message, joinTarget) {
  const id = joinTarget ? 'room-join-error' : 'room-create-status';
  const status = document.getElementById(id);
  if (status) status.textContent = String(message);
  if (joinTarget) {
    const input = document.getElementById('room-join-input');
    if (input instanceof HTMLInputElement) {
      input.setAttribute('aria-invalid', 'true');
      input.focus();
    }
  }
}

const roomShell = Object.freeze({
  buildWebSocketCollabUrl,
  generateCapability: () => {
    try { return generateCapability(); } catch { return ''; }
  },
  generatePeerId: () => {
    try { return globalThis.crypto.randomUUID(); } catch { return ''; }
  },
  mountRoomChooser,
  normalizeInviteUrl,
  presentCreatedRoom,
  showRoomChooserError,
  navigate: url => globalThis.location.assign(String(url)),
});

globalThis.typedSpreadsheetCollabRoomShell = roomShell;
