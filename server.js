const express = require('express');
const app = express();
const PORT = process.olar || 3000;

app.use(express.json());

// نقطة التحقق من صحة النظام والذكاء الاصطناعي
app.get('/api/health', (req, res) => {
    res.json({ status: 'success', message: 'Al-Faeq Yemen Backend is running smoothly! 🚀', ai_maintenance: 'Active' });
});

// مسار جلب الأقسام التجارية الثمانية
app.get('/api/categories', (req, res) => {
    res.json([
        { id: 1, name: 'الملابس والأزياء' },
        { id: 2, name: 'أدوات التجميل والعناية' },
        { id: 3, name: 'المطاعم والوجبات' },
        { id: 4, name: 'السوبرماركت والغذائيات' },
        { id: 5, name: 'الفنادق والحجوزات' },
        { id: 6, name: 'الصيدليات والأدوية' },
        { id: 7, name: 'المستشفيات والمراكز' },
        { id: 8, name: 'التوصيل والخدمات المالية' }
    ]);
});

// تشغيل السيرفر
app.listen(3000, () => {
    console.log('Al-Faeq Yemen Server is running on port 3000');
});
