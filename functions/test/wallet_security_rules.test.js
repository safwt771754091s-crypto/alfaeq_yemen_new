const fs = require('fs');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

describe('wallet Firestore security rules', () => {
  let testEnv;

  beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: 'alfaeq-yemen-wallet-rules-test',
      firestore: {
        rules: fs.readFileSync('firestore.rules', 'utf8'),
      },
    });
  });

  afterAll(async () => {
    await testEnv.cleanup();
  });

  test('customer cannot tamper with wallet balance', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    const db = ctx.firestore();
    await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
      await adminCtx.firestore().doc('wallets/alice').set({
        uid: 'alice', currency: 'YER', availableBalance: 1000,
        reservedBalance: 0, status: 'active', version: 1,
      });
    });
    await assertFails(db.doc('wallets/alice').update({ availableBalance: 999999 }));
  });

  test('customer cannot create ledger transactions directly', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    await assertFails(ctx.firestore().doc('walletTransactions/fake').set({
      uid: 'alice', type: 'transfer_debit', amount: 100,
      currency: 'YER', createdAt: new Date(),
    }));
  });

  test('customer cannot mutate an operation after creation', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
      await adminCtx.firestore().doc('walletOperations/op1').set({
        uid: 'alice', type: 'transfer', recipientUid: 'bob', amount: 100,
        status: 'pending', currency: 'YER', createdAt: new Date(),
      });
    });
    await assertFails(ctx.firestore().doc('walletOperations/op1').update({ status: 'completed' }));
    await assertFails(ctx.firestore().doc('walletOperations/op1').delete());
  });

  test('customer cannot spoof another uid', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    await assertFails(ctx.firestore().doc('walletOperations/op2').set({
      uid: 'bob', type: 'transfer', recipientUid: 'carol', amount: 100,
      status: 'pending', currency: 'YER', createdAt: new Date(),
    }));
  });

  test('customer cannot create transfer without a recipient', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    await assertFails(ctx.firestore().doc('walletOperations/op3').set({
      uid: 'alice', type: 'transfer', amount: 100,
      status: 'pending', currency: 'YER', createdAt: new Date(),
    }));
  });

  test('customer cannot create transfer to self', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    await assertFails(ctx.firestore().doc('walletOperations/op4').set({
      uid: 'alice', type: 'transfer', recipientUid: 'alice', amount: 100,
      status: 'pending', currency: 'YER', createdAt: new Date(),
    }));
  });

  test('customer cannot inject server-controlled fields', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    await assertFails(ctx.firestore().doc('walletOperations/op5').set({
      uid: 'alice', type: 'deposit', amount: 100,
      status: 'pending', currency: 'YER', createdAt: new Date(),
      availableBalance: 999999, processedAt: new Date(),
      rejectionCode: 'NONE',
    }));
  });

  test('customer cannot create non-YER operations', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    await assertFails(ctx.firestore().doc('walletOperations/op6').set({
      uid: 'alice', type: 'deposit', amount: 100,
      status: 'pending', currency: 'USD', createdAt: new Date(),
    }));
  });

  test('valid customer operation is allowed', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    const now = new Date();
    await assertSucceeds(ctx.firestore().doc('walletOperations/op7').set({
      uid: 'alice', type: 'transfer', recipientUid: 'bob', amount: 100,
      status: 'pending', currency: 'YER', createdAt: now,
    }));
  });
});
