const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');
const { getSarToYerRate, sarToYer } = require('../functions/currency');

initializeApp();
const db = getFirestore();
const CHUNKS = ['catalog_01.json','catalog_02.json','catalog_03.json','catalog_04.json','catalog_05.json','catalog_06.json','catalog_07.json','catalog_08.json'];
const BATCH_SIZE = 100; // Small commits reduce pressure on Firestore during imports.
const MAX_RETRIES = 6;

function imageUrlForBarcode(barcode) {
  const digits = String(barcode || '').replace(/\\D/g, '');
  if (digits.length < 8) return null;
  return `https://images.openfoodfacts.org/images/products/${digits.slice(0,3)}/${digits.slice(3,6)}/${digits.slice(6,9)}/${digits.slice(9)}/front_en.400.jpg`;
}
function normalizeUnit(raw) {
  const u = String(raw || '').trim().toLowerCase();
  if (['كجم','كيلو','كيلوجرام','kg'].includes(u)) return 'kg';
  if (['جرام','غرام','g','جم'].includes(u)) return 'g';
  if (['لتر','ل','liter','l'].includes(u)) return 'l';
  if (['مل','ملي','ml'].includes(u)) return 'ml';
  if (['متر','m'].includes(u)) return 'm';
  return 'piece';
}
function unitScale(unit) { return { piece:1, kg:1000, g:1, l:1000, ml:1, m:1 }[unit] || 1; }
function validPrice(v) { return typeof v === 'number' && Number.isFinite(v) && v >= 0; }

async function commitWithRetry(batch, label) {
  for (let attempt = 0; ; attempt++) {
    try {
      await batch.commit();
      return;
    } catch (error) {
      const code = error?.code;
      const retryable = code === 4 || code === 8 || code === 10 || code === 13 || code === 14 ||
        ['RESOURCE_EXHAUSTED','ABORTED','UNAVAILABLE','DEADLINE_EXCEEDED','INTERNAL'].includes(error?.status);
      if (!retryable || attempt >= MAX_RETRIES) {
        error.message = `${label} failed after ${attempt + 1} attempt(s): ${error.message}`;
        throw error;
      }
      const delayMs = Math.min(60000, 1500 * (2 ** attempt)) + Math.floor(Math.random() * 1000);
      console.warn(`${label}: transient Firestore error (${code || error.status || 'unknown'}); retry ${attempt + 1}/${MAX_RETRIES} in ${delayMs}ms`);
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
}

async function findOwnerId() {
  const ownerSnap = await db.collection('users').where('role', '==', 'owner').limit(1).get();
  if (!ownerSnap.empty) return ownerSnap.docs[0].id;
  const adminSnap = await db.collection('users').where('role', '==', 'admin').limit(1).get();
  if (!adminSnap.empty) return adminSnap.docs[0].id;
  return 'admin-created';
}

async function main() {
  const ownerId = await findOwnerId();
  const sarToYerRate = await getSarToYerRate(db);
  await db.collection('stores').doc('super-alfaeq').set({
    name:'سوبر الفائق', sectionId:'markets', ownerId, status:'approved', enabled:true,
    address:'سوبر الفائق — متجر المنصة', phone:'', catalogSource:'excel_2026_09_19',
    updatedAt:FieldValue.serverTimestamp(), createdAt:FieldValue.serverTimestamp()
  }, {merge:true});

  let imported=0, active=0, rowIndex=0, totalBatches=0;
  let batch=db.batch(), writes=0;
  for (const file of CHUNKS) {
    const rows=JSON.parse(fs.readFileSync(path.join(__dirname,'..','functions','data','super_alfaeq',file),'utf8'));
    for (const row of rows) {
      rowIndex++;
      const productId=`super_${String(row.id).replace(/[^A-Za-z0-9_-]/g,'_')}_${rowIndex}`.slice(0,120);
      const saleUnit=normalizeUnit(row.unit), scale=unitScale(saleUnit);
      const priceSar=Number(row.price || 0), costSar=Number(row.cost || 0);
      const stockRaw=Number(row.stock ?? 0), expectedStock=Number(row.expectedStock ?? 0);
      const stock=stockRaw > 0 ? stockRaw : expectedStock;
      const price=sarToYer(priceSar, sarToYerRate), cost=sarToYer(costSar, sarToYerRate);
      const status=validPrice(price)?'active':'draft';
      if(status==='active') active++;
      batch.set(db.collection('products').doc(productId), {
        name:String(row.name || 'منتج'), barcode:row.barcode || null,
        internalRef:row.internalRef || null, reference:row.internalRef || row.barcode || productId,
        category:String(row.category || 'عام'), price:validPrice(price)?price:0,
        priceSar:validPrice(priceSar)?priceSar:0, cost:validPrice(cost)?cost:0, costSar:validPrice(costSar)?costSar:0,
        currency:'YER', sourceCurrency:'SAR', exchangeRateSarToYer:sarToYerRate, stock,
        stockSource:stockRaw > 0 ? 'stock' : (expectedStock > 0 ? 'expectedStock' : 'unverified'),
        stockBase:Math.max(0,Math.round(stock*scale)), expectedStock,
        saleUnit, unitScale:scale,
        baseUnit:['kg','g'].includes(saleUnit)?'g':(['l','ml'].includes(saleUnit)?'ml':saleUnit),
        stepBase:(saleUnit==='kg'||saleUnit==='l')?250:1,
        minOrderBase:(saleUnit==='kg'||saleUnit==='l')?250:1,
        storeId:'super-alfaeq', ownerId, merchantName:'سوبر الفائق', status,
        imageUrl:imageUrlForBarcode(row.barcode), imagePath:row.imagePath || null,
        imageStatus:row.imageStatus || null, priceReview:row.priceReview || null,
        source:'excel_import', sourceFile:'الفائق_يمن_منتجات_سوبر_الفائق_جاهز_للمراجعة.xlsx',
        updatedAt:FieldValue.serverTimestamp(), createdAt:FieldValue.serverTimestamp()
      }, {merge:true});
      imported++; writes++;
      if(writes >= BATCH_SIZE){
        await commitWithRetry(batch, `Firestore batch ${++totalBatches}`);
        console.log(`committed batch ${totalBatches}; processed ${imported} products`);
        batch=db.batch(); writes=0;
        // Brief pause smooths sustained write pressure. Re-running is safe because IDs are deterministic.
        await new Promise(resolve => setTimeout(resolve, 300));
      }
    }
    console.log(`read ${file}: ${rows.length} rows`);
  }
  if(writes){ await commitWithRetry(batch, `Firestore batch ${++totalBatches}`); }
  await db.collection('settings').doc('super_alfaeq_catalog').set({
    status:'ready', source:'الفائق_يمن_منتجات_سوبر_الفائق_جاهز_للمراجعة.xlsx',
    imported, active, storeId:'super-alfaeq', ownerId, seededBy:'github_actions',
    sarToYerRate, baseCurrency:'YER', sourceCurrency:'SAR',
    completedAt:FieldValue.serverTimestamp(), updatedAt:FieldValue.serverTimestamp()
  }, {merge:true});
  console.log(JSON.stringify({ok:true, imported, active, totalBatches, ownerId}));
}
main().catch(error=>{console.error(error);process.exit(1);});
