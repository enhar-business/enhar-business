const pageInfo={dashboard:"لوحة التحكم",pos:"نقطة البيع",sales:"المبيعات والفواتير",purchases:"المشتريات",inventory:"المخزون والأصناف",contacts:"العملاء والموردون",accounting:"المحاسبة والقيود",cash:"الصناديق والورديات",reports:"التقارير والتحليلات",branches:"الفروع ومراكز التكلفة",team:"المستخدمون والصلاحيات",approvals:"الموافقات وسير العمل",settings:"إعدادات المنشأة"};
const nav=[...document.querySelectorAll("[data-page]")];const pageWrap=document.getElementById("pageWrap");const sidebar=document.getElementById("sidebar");const overlay=document.getElementById("overlay");const toast=document.getElementById("toast");
function notify(message){toast.textContent=message;toast.classList.add("show");clearTimeout(notify.timer);notify.timer=setTimeout(()=>toast.classList.remove("show"),2600)}
function renderPage(key){if(key==="dashboard"){location.reload();return}const title=pageInfo[key]||"لوحة التحكم";document.getElementById("crumbTitle").textContent=title;nav.forEach(n=>n.classList.toggle("active",n.dataset.page===key));pageWrap.innerHTML=`<div class="page-heading"><div><div class="overline">إدارة المنشأة / ${title}</div><h1>${title}</h1><p>مساحة العمل المخصصة لإدارة ${title} ضمن منصة ANHAR.</p></div><button class="btn btn-outline" id="backDashboard"><i data-lucide="arrow-right"></i> العودة للوحة التحكم</button></div><div class="demo-notice"><i data-lucide="info"></i><span><b>الوحدة قيد التأسيس.</b> هذه الشاشة لم تُربط بعد بقاعدة البيانات؛ لن نوهمك بأن الحفظ أو العمليات المالية تعمل قبل تنفيذها واختبارها.</span></div><section class="panel" style="min-height:300px;display:grid;place-items:center;text-align:center"><div><div class="chart-art" style="margin:0 auto 14px"><i data-lucide="construction"></i></div><h2 style="font-size:15px">${title}</h2><p style="font-size:11px;color:var(--muted);max-width:440px;line-height:2">سيتم بناء هذه الوحدة وربطها بالصلاحيات والبيانات وسجل التدقيق واختبارها من البداية إلى النهاية قبل اعتمادها.</p><button class="btn btn-outline" id="backDashboard2">العودة إلى لوحة التحكم</button></div></section>`;document.getElementById("backDashboard").onclick=()=>location.reload();document.getElementById("backDashboard2").onclick=()=>location.reload();if(window.lucide)lucide.createIcons();sidebar.classList.remove("open");overlay.classList.remove("show")}
nav.forEach(n=>n.addEventListener("click",()=>renderPage(n.dataset.page)));document.getElementById("menuToggle").addEventListener("click",()=>{sidebar.classList.toggle("open");overlay.classList.toggle("show")});overlay.addEventListener("click",()=>{sidebar.classList.remove("open");overlay.classList.remove("show")});document.getElementById("noticeClose").addEventListener("click",()=>document.querySelector(".demo-notice").remove());document.getElementById("periodBtn").addEventListener("click",()=>notify("سيتم تفعيل الفلاتر الزمنية بعد ربط البيانات."));document.querySelector(".notification-btn").addEventListener("click",()=>notify("لا توجد تنبيهات جديدة."));document.addEventListener("keydown",e=>{if(e.key==="F2"){e.preventDefault();renderPage("pos")}if(e.key==="Escape"){sidebar.classList.remove("open");overlay.classList.remove("show")}});if(window.lucide)lucide.createIcons();


// Supabase browser client bootstrap. Publishable keys are intended for browser use;
// all database access must still be protected by reviewed RLS policies.
(async function initializeAnharSupabase(){
  const status=document.querySelector(".system-status");
  if(!window.ANHAR_SUPABASE_CONFIG || !window.supabase?.createClient){
    if(status) status.innerHTML='<span></span> إعداد الاتصال غير مكتمل';
    return;
  }
  const {url,key}=window.ANHAR_SUPABASE_CONFIG;
  const client=window.supabase.createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
  window.ANHAR_SUPABASE=client;
  try{
    const response=await fetch(url+"/auth/v1/health",{method:"GET",headers:{apikey:key}});
    if(status) status.innerHTML=response.ok?'<span></span> اتصال Supabase متاح':'<span></span> تم إعداد المفتاح — تحقق من الاتصال';
  }catch(error){
    if(status) status.innerHTML='<span></span> تم إعداد Supabase — تعذر التحقق من الشبكة';
  }
})();
