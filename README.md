# 🛡️ Radius-Streamnet — حزمة التوزيع المحصنة (Debian/Ubuntu Package)

يحتوي هذا المجلد على حزمة التوزيع المستقلة والمحمية لنظام **Radius-Streamnet** بصيغة **`.deb`**، جاهزة للتثبيت المباشر على خوادم **Ubuntu** أو **Debian**.

---

## 🔒 مواصفات الحماية والتحصين المطبقة

تم بناء الحزمة بأعلى معايير الحماية وإغلاق الكود البرمجي (Proprietary Production Hardening):

1. **التشويش البرمجي الكامل (Garble Obfuscation):**
   - تشفير النصوص الثابتة (Literals Encryption) بما فيها أسماء المسارات، جمل SQL، ورسائل الخطأ.
   - تشويش وإخفاء أسماء الدوال (Function Names) والمتحولات والحزم البرمجية بالكامل.
2. **نزع الرموز ومعلومات التطوير (Symbol Stripping):**
   - استخدام خيارات `-ldflags="-s -w"` لحذف Symbol Table ومعلومات DWARF debug info.
3. **حذف مسارات السورس كود (Trimpath):**
   - استخدام خيار `-trimpath` لمنع ظهور أي مسارات للمجلدات الأصلية أو مسار السيرفر داخل الملف التنفيذي.
4. **حماية الترخيص والربط بالعتاد:**
   - الحزمة مرتبطة بنظام الترخيص المدمج (`license.go`) وتتطلب ترخيصاً رقمياً للتشغيل.

---

## 📦 محتويات المجلد

- **`radius-streamnet_2.4.0_amd64.deb`**: الحزمة النهائية المترجمة والمحمية، حجمها حوالي **27.5 ميجابايت** مضغوطة وتحتوي على النظام بالكامل مدمجاً بداخله واجهات الويب.
- **`install.sh`**: سكربت التثبيت السريع للعميل بضغطة زر واحدة.
- **`build-deb.sh`**: سكربت إعادة بناء الحزمة تلقائياً في أي وقت عند تحديث الكود.
- **`package-template/`**: ملفات التحكم وهيكل الحزمة (`control`, `postinst`, `systemd.service`).

---

## 🚀 طريقة التثبيت على أي سيرفر عميل جديد (Ubuntu / Debian)

### الطريقة 1: التثبيت السريع عبر سكربت التثبيت:
```bash
sudo bash install.sh
```

### الطريقة 2: التثبيت اليدوي عبر أمر `apt` أو `dpkg`:
```bash
# 1. تثبيت الحزمة تلقائياً مع حل كافة التبعيات:
sudo apt install ./radius-streamnet_2.4.0_amd64.deb

# أو عبر dpkg:
sudo dpkg -i radius-streamnet_2.4.0_amd64.deb
sudo apt-get install -f -y
```

---

## ⚙️ التحكم في الخدمة بعد التثبيت

بمجرد التثبيت، تعمل الخدمة تلقائياً في الخلفية تحت إدارة `systemd`:

```bash
# التحقق من حالة التشغيل
sudo systemctl status streamnet.service

# إعادة تشغيل النظام
sudo systemctl restart streamnet.service

# إيقاف النظام
sudo systemctl stop streamnet.service

# متابعة السجلات اللحظية (Live Logs)
sudo journalctl -u streamnet.service -f
```

---

## 🔨 كيفية إعادة بناء حزمة `.deb` جديدة بعد التعديلات

إذا قمت بأي تعديلات برمجية على النظام وتريد إصدار ملف `.deb` جديد:

```bash
cd RadiusDeploy
chmod +x build-deb.sh
./build-deb.sh
```
سيقوم السكربت تلقائياً باستدعاء أداة التشفير `garble`، تصريف الكود، وحزم ملف الـ `.deb` الجديد.
