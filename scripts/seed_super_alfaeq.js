const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');

initializeApp();
const db = getFirestore();
const CHUNKS = ['catalog_01.json','catalog_02.json','catalog_03.json','catalog_04.json','catalog_05.json','catalog_06.json','catalog_07.json','catalog_08.json'];

function imageUrlForBarcode(barcode) {
  const digits = String(barcode || '').replace(/\D/g, '');
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

async function findOwnerId() {
  const ownerSnap = await db.collection('users').where('role', '==', 'owner').limit(1).get();
  if (!ownerSnap.empty) return ownerSnap.docs[0].id;
  const adminSnap = await db.collection('users').where('role', '==', 'admin').limit(1).get();
  if (!adminSnap.empty) return adminSnap.docs[0].id;
  return 'admin-created';
}

async function main() {
  const ownerId = await findOwnerId();
  await db.collection('stores').doc('super-alfaeq').set({
    name:'سوبر الفائق', sectionId:'markets', ownerId, status:'approved', enabled:true,
    address:'سوبر الفائق — متجر المنصة', phone:'', catalogSource:'excel_2026_09_19',
    updatedAt:FieldValue.serverTimestamp(), createdAt:FieldValue.serverTimestamp()
  }, {merge:true});

  let imported=0, active=0, rowIndex=0;
  for (const file of CHUNKS) {
    const rows=JSON.parse(fs.readFileSync(path.join(__dirname,'..','functions','data','super_alfaeq',file),'utf8'));
    let batch=db.batch(), writes=0;
    for (const row of rows) {
      rowIndex++;
      const productId=`super_${String(row.id).replace(/[^A-Za-z0-9_-]/g,'_')}_${rowIndex}`.slice(0,120);
      const saleUnit=normalizeUnit(row.unit), scale=unitScale(saleUnit);
      const price=Number(row.price || 0), stock=Number(row.stock || 0);
      const status=validPrice(price)?'active':'draft';
      if(status==='active') active++;
      batch.set(db.collection('products').doc(productId), {
        name:String(row.name || 'منتج'), barcode:row.barcode || null,
        internalRef:row.internalRef || null, reference:row.internalRef || row.barcode || productId,
        category:String(row.category || 'عام'), price:validPrice(price)?price:0,
        cost:Number(row.cost || 0), currency:'YER', stock,
        stockBase:Math.max(0,Math.round(stock*scale)), expectedStock:Number(row.expectedStock || 0),
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
      if(writes===450){ await batch.commit(); batch=db.batch(); writes=0; }
    }
    if(writes) await batch.commit();
    console.log(`seeded ${file}: ${rows.length} rows`);
  }
  await db.collection('settings').doc('super_alfaeq_catalog').set({
    status:'ready', source:'الفائق_يمن_منتجات_سوبر_الفائق_جاهز_للمراجعة.xlsx',
    imported, active, storeId:'super-alfaeq', ownerId, seededBy:'github_actions',
    completedAt:FieldValue.serverTimestamp(), updatedAt:FieldValue.serverTimestamp()
  }, {merge:true});
  console.log(JSON.stringify({ok:true, imported, active, ownerId}));
}
main().catch(error=>{console.error(error);process.exit(1);});
