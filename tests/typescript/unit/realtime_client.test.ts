import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ArlenRealtimeResyncRequiredError,
  ArlenRealtimeStreamClient,
  arlenRealtimeNextCursor,
  arlenRealtimeReplayPath,
  arlenRealtimeTransportPlan,
} from '../generated/arlen/src/realtime.ts';

test('realtime transport plan falls back to supported transports deterministically', () => {
  const noBrowserPlan = arlenRealtimeTransportPlan({
    transports: ['websocket', 'sse', 'poll'],
  });
  assert.deepEqual(noBrowserPlan, ['poll']);

  const websocketPlan = arlenRealtimeTransportPlan({
    transports: ['websocket', 'poll'],
    websocketFactory: () => ({}) as WebSocket,
  });
  assert.deepEqual(websocketPlan, ['websocket', 'poll']);
});

test('realtime replay path stays deterministic and query-shaped', () => {
  assert.equal(
    arlenRealtimeReplayPath('conversation:33', 41, 50, 75),
    '/streams/conversation%3A33/events?after_sequence=41&limit=50&replay_window=75'
  );
});

test('realtime client poll transport advances cursor from replay payload', async () => {
  const calls: string[] = [];
  const client = new ArlenRealtimeStreamClient<{ body: string }>({
    baseUrl: 'http://127.0.0.1:3000',
    streamId: 'conversation:33',
    cursor: 1,
    transports: ['poll'],
    fetch: async (input: RequestInfo | URL) => {
      calls.push(String(input));
      return new Response(
        JSON.stringify({
          stream_id: 'conversation:33',
          events: [
            {
              stream_id: 'conversation:33',
              sequence: 2,
              event_id: 'evt_2',
              event_type: 'message_created',
              occurred_at: '2026-04-15T21:00:01Z',
              payload: {
                body: 'hello',
              },
            },
          ],
          latest_cursor: {
            stream_id: 'conversation:33',
            sequence: 2,
          },
          replay_limit: 100,
          replay_window: 100,
        }),
        {
          status: 200,
          headers: {
            'content-type': 'application/json',
          },
        }
      );
    },
  });

  const transport = await client.connect();
  assert.equal(transport, 'poll');
  assert.equal(client.snapshot().activeTransport, 'poll');
  assert.equal(client.snapshot().state, 'live');
  assert.equal(client.snapshot().cursor, 2);
  assert.equal(calls.length, 1);
  assert.match(calls[0]!, /after_sequence=1/);
});

test('realtime client raises resync-required error deterministically', async () => {
  const client = new ArlenRealtimeStreamClient({
    streamId: 'conversation:33',
    cursor: 0,
    transports: ['poll'],
    fetch: async () =>
      new Response(
        JSON.stringify({
          status: 'resync_required',
          stream_id: 'conversation:33',
          latest_cursor: {
            stream_id: 'conversation:33',
            sequence: 9,
          },
          replay_limit: 1,
          replay_window: 1,
          requested_after_sequence: 0,
        }),
        {
          status: 409,
          headers: {
            'content-type': 'application/json',
          },
        }
      ),
  });

  await assert.rejects(async () => client.pollOnce(), (error: unknown) => {
    assert.ok(error instanceof ArlenRealtimeResyncRequiredError);
    assert.equal(error.payload.latest_cursor.sequence, 9);
    return true;
  });
  assert.equal(client.snapshot().state, 'resync-required');
});

test('realtime next cursor falls back when no events exist', () => {
  assert.equal(arlenRealtimeNextCursor([], 12), 12);
});
