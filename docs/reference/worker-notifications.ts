import { json, getMissingBindings } from '../lib/types'
import type { Env } from '../lib/types'
import { getAccessToken, getFirebaseUserFromIdToken, getFirestoreUser } from '../lib/firebase'

// ─── Notification event registry ─────────────────────────────────────────────

export const NOTIFICATION_EVENTS = {
  'roster-published':    { title: 'Roster published',           body: 'Your new shifts are ready to view.',                    url: '/staff/roster' },
  'timesheet-submitted': { title: 'Timesheet submitted',        body: 'A staff member submitted hours for review.',            url: '/manager/timesheets' },
  'timesheet-approved':  { title: 'Timesheet approved',         body: 'Your submitted hours were approved.',                   url: '/staff/history' },
  'timesheet-rejected':  { title: 'Timesheet needs changes',    body: 'Your submitted hours were rejected. Tap to review.',    url: '/staff/history' },
  'timesheet-absent':    { title: 'Absence reported',           body: 'A staff member reported they did not attend a shift.', url: '/manager/timesheets' },
  'timesheet-reminder':  { title: 'Hours submission reminder',  body: 'Please submit your hours for your completed shift.',    url: '/staff/roster' },
  'message-task':        { title: 'New task',                   body: 'Your manager assigned you a task.',                     url: '/staff/home' },
  'shift-start-6h':      { title: 'Shift starting soon',        body: 'Your shift starts in 6 hours.',                         url: '/staff/roster' },
  'shift-start-30m':     { title: 'Shift starting soon',        body: 'Your shift starts in 30 minutes.',                      url: '/staff/roster' },
} as const

export type NotificationEvent = keyof typeof NOTIFICATION_EVENTS
export const NOTIFICATION_EVENT_NAMES = Object.keys(NOTIFICATION_EVENTS) as NotificationEvent[]

// ─── Recipient resolution (pure — unit-testable) ──────────────────────────────

export interface NotificationCallerProfile { uid: string; role?: string; status?: string }
export interface NotificationRequestInput {
  event: NotificationEvent; shiftIds?: string[]; timesheetId?: string; recipientIds?: string[]
}
export interface NotificationRecipientResolvers {
  getShiftStaffIds: (shiftIds: string[]) => Promise<string[]>
  listActiveManagerIds: () => Promise<string[]>
  getTimesheetStaffId: (timesheetId: string) => Promise<string | null>
}
export type RecipientResolution = { ok: true; recipientUids: string[] } | { ok: false; status: number; error: string }

export async function resolveNotificationRecipients(
  caller: NotificationCallerProfile,
  input: NotificationRequestInput,
  resolvers: NotificationRecipientResolvers,
): Promise<RecipientResolution> {
  const { event } = input
  const managerOnly = (): RecipientResolution | null =>
    caller.role !== 'manager' ? { ok: false, status: 403, error: 'Only managers can send this notification' } : null

  let recipientUids: string[] = []

  if (event === 'roster-published') {
    const denied = managerOnly(); if (denied) return denied
    const shiftIds = (input.shiftIds || []).filter((id): id is string => typeof id === 'string' && Boolean(id)).slice(0, 300)
    recipientUids = await resolvers.getShiftStaffIds(shiftIds)
  } else if (event === 'message-task') {
    const denied = managerOnly(); if (denied) return denied
    recipientUids = (input.recipientIds || []).filter((id): id is string => typeof id === 'string' && Boolean(id)).slice(0, 500)
  } else if (event === 'timesheet-submitted' || event === 'timesheet-absent') {
    recipientUids = await resolvers.listActiveManagerIds()
  } else if (event === 'timesheet-approved' || event === 'timesheet-rejected') {
    const denied = managerOnly(); if (denied) return denied
    const timesheetId = typeof input.timesheetId === 'string' ? input.timesheetId : ''
    const staffId = timesheetId ? await resolvers.getTimesheetStaffId(timesheetId) : null
    recipientUids = staffId ? [staffId] : []
  } else {
    return { ok: false, status: 400, error: 'Unknown notification event' }
  }

  const unique = [...new Set(recipientUids)].filter(uid => Boolean(uid) && uid !== caller.uid)
  return { ok: true, recipientUids: unique }
}

// ─── FCM helpers ──────────────────────────────────────────────────────────────

export function buildFcmMessage(token: string, content: { title: string; body: string; url: string }) {
  return {
    message: {
      token,
      data: {
        title: content.title,
        body: content.body,
        url: content.url,
      },
      webpush: { headers: { Urgency: 'high', TTL: '86400' } },
    },
  }
}

async function listUserNotificationTokens(uid: string, accessToken: string, env: Env) {
  const base = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${uid}/notificationTokens?pageSize=300`
  const tokens: Array<{ docId: string; token: string; enabled: boolean }> = []
  let pageToken: string | undefined
  for (let page = 0; page < 50; page++) {
    const url = pageToken ? `${base}&pageToken=${encodeURIComponent(pageToken)}` : base
    const response = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } })
    if (response.status === 404) break
    const body = await response.json() as {
      documents?: Array<{ name?: string; fields?: { token?: { stringValue?: string }; enabled?: { booleanValue?: boolean } } }>
      nextPageToken?: string
    }
    if (!response.ok || !Array.isArray(body.documents)) break
    for (const doc of body.documents) {
      const entry = { docId: doc.name?.split('/').pop() || '', token: doc.fields?.token?.stringValue || '', enabled: doc.fields?.enabled?.booleanValue !== false }
      if (entry.docId && entry.token && entry.enabled) tokens.push(entry)
    }
    if (!body.nextPageToken) break
    pageToken = body.nextPageToken
  }
  return tokens
}

async function deleteUserNotificationToken(uid: string, docId: string, accessToken: string, env: Env) {
  await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${uid}/notificationTokens/${docId}`,
    { method: 'DELETE', headers: { Authorization: `Bearer ${accessToken}` } }
  )
}

async function sendFcmMessage(token: string, content: { title: string; body: string; url: string }, accessToken: string, env: Env): Promise<{ ok: boolean; stale: boolean }> {
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(buildFcmMessage(token, content)),
  })
  if (response.ok) return { ok: true, stale: false }
  const body = await response.json().catch(() => ({})) as { error?: { status?: string } }
  const status = body.error?.status
  return { ok: false, stale: response.status === 404 || status === 'UNREGISTERED' || status === 'NOT_FOUND' }
}

export async function notifyUsers(uids: string[], content: { title: string; body: string; url: string }, accessToken: string, env: Env): Promise<number> {
  const uniqueUids = [...new Set(uids)].filter(Boolean)
  let sent = 0
  for (const uid of uniqueUids) {
    const tokens = await listUserNotificationTokens(uid, accessToken, env)
    for (const t of tokens) {
      const result = await sendFcmMessage(t.token, content, accessToken, env)
      if (result.ok) { sent++ }
      else if (result.stale) { await deleteUserNotificationToken(uid, t.docId, accessToken, env).catch(() => undefined) }
    }
  }
  return sent
}

async function listActiveManagerIds(accessToken: string, env: Env): Promise<string[]> {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:runQuery`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'users' }], where: { fieldFilter: { field: { fieldPath: 'role' }, op: 'EQUAL', value: { stringValue: 'manager' } } } } }),
  })
  const body = await response.json().catch(() => null) as Array<{ document?: { name?: string; fields?: { status?: { stringValue?: string } } } }> | { error?: { message?: string; status?: string } } | null
  if (!response.ok || !Array.isArray(body)) {
    const reason = body && !Array.isArray(body) ? (body as { error?: { message?: string; status?: string } }).error?.message || (body as { error?: { message?: string; status?: string } }).error?.status : `HTTP ${response.status}`
    console.warn('listActiveManagerIds query failed', reason)
    return []
  }
  const managerIds = body.filter(row => { const s = row.document?.fields?.status?.stringValue; return s !== 'inactive' && s !== 'locked' })
    .map(row => row.document?.name?.split('/').pop()).filter((id): id is string => Boolean(id))
  if (managerIds.length === 0) console.warn('listActiveManagerIds resolved no active managers')
  return managerIds
}

async function getShiftStaffIds(shiftIds: string[], accessToken: string, env: Env): Promise<string[]> {
  if (shiftIds.length === 0) return []
  const documents = shiftIds.map(id => `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/shifts/${id}`)
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:batchGet`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ documents }),
  })
  const body = await response.json() as Array<{ found?: { fields?: { staffId?: { stringValue?: string } } } }>
  if (!response.ok || !Array.isArray(body)) return []
  return body.map(row => row.found?.fields?.staffId?.stringValue).filter((id): id is string => Boolean(id))
}

async function getTimesheetStaffId(timesheetId: string, accessToken: string, env: Env): Promise<string | null> {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/timesheets/${timesheetId}`, { headers: { Authorization: `Bearer ${accessToken}` } })
  if (response.status === 404) return null
  const body = await response.json() as { fields?: { staffId?: { stringValue?: string } } }
  if (!response.ok) return null
  return body.fields?.staffId?.stringValue || null
}

// ─── Handler ──────────────────────────────────────────────────────────────────

export async function handleSendNotification(request: Request, env: Env): Promise<Response> {
  const missing = getMissingBindings(env)
  if (missing.length > 0) return json({ ok: false, skipped: true, reason: `Notifications missing Worker config: ${missing.join(', ')}` }, 200)

  const idToken = (request.headers.get('Authorization') || '').replace('Bearer ', '')
  if (!idToken) return json({ error: 'Not authenticated' }, 401)

  let body: { event?: unknown; shiftIds?: unknown; timesheetId?: unknown; recipientIds?: unknown }
  try { body = await request.json() } catch { return json({ error: 'Invalid request body' }, 400) }

  const event = body.event
  if (typeof event !== 'string' || !(event in NOTIFICATION_EVENTS)) return json({ error: 'Unknown notification event' }, 400)
  const typedEvent = event as NotificationEvent

  const accessToken = await getAccessToken(env)
  const caller = await getFirebaseUserFromIdToken(idToken, env)
  if (!caller?.localId) return json({ error: 'Invalid session' }, 401)

  const callerProfile = await getFirestoreUser(caller.localId, accessToken, env)
  if (!callerProfile || callerProfile.status === 'inactive' || callerProfile.status === 'locked') return json({ error: 'Account is not active' }, 403)

  const resolution = await resolveNotificationRecipients(
    { uid: caller.localId, role: callerProfile.role, status: callerProfile.status },
    {
      event: typedEvent,
      shiftIds: Array.isArray(body.shiftIds) ? (body.shiftIds as string[]) : undefined,
      timesheetId: typeof body.timesheetId === 'string' ? body.timesheetId : undefined,
      recipientIds: Array.isArray(body.recipientIds) ? (body.recipientIds as string[]) : undefined,
    },
    {
      getShiftStaffIds: (ids) => getShiftStaffIds(ids, accessToken, env),
      listActiveManagerIds: () => listActiveManagerIds(accessToken, env),
      getTimesheetStaffId: (id) => getTimesheetStaffId(id, accessToken, env),
    },
  )
  if (!resolution.ok) return json({ error: resolution.error }, resolution.status)

  const baseContent = NOTIFICATION_EVENTS[typedEvent]
  let bodyText: string = baseContent.body
  const name = callerProfile.fullName
  if (typedEvent === 'timesheet-submitted') bodyText = `${name || 'A staff member'} submitted hours for review.`
  else if (typedEvent === 'timesheet-absent') bodyText = `${name || 'A staff member'} reported they did not attend a shift.`
  else if (typedEvent === 'roster-published') bodyText = `${name || 'Your manager'} published your new shifts.`
  else if (typedEvent === 'timesheet-approved') bodyText = `${name || 'Your manager'} approved your submitted hours.`
  else if (typedEvent === 'timesheet-rejected') bodyText = `${name || 'Your manager'} rejected your timesheet. Tap to review.`
  else if (typedEvent === 'message-task') bodyText = `${name || 'Your manager'} assigned you a task.`

  const sent = await notifyUsers(resolution.recipientUids, { ...baseContent, body: bodyText }, accessToken, env)
  return json({ ok: true, event: typedEvent, recipients: resolution.recipientUids.length, sent })
}
