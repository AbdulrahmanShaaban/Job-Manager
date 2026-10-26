import { Type, type FunctionDeclaration, type LiveConnectConfig, Modality } from "@google/genai";
import { CAIRO_TIME_ZONE, todayInCairo } from "../../shared/dates.ts";

const text = (description: string) => ({ type: Type.STRING, description });
const dateOnly = (description: string) => ({
  type: Type.STRING,
  description: `${description} (YYYY-MM-DD)`,
  format: "date",
});

export const TOOL_DECLARATIONS: FunctionDeclaration[] = [
  {
    name: "searchSites",
    description:
      "ابحث في مواقع المستخدم ومواقع شركته المسموح له بها بالاسم أو العنوان. استخدمها أولاً لما المستخدم يذكر موقع.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "اسم الموقع أو جزء من العنوان" },
        limit: { type: "integer", minimum: 1, maximum: 20 },
      },
      required: [],
    },
  },
  {
    name: "getSiteSummary",
    description:
      "هات ملخص موقع محدد: العنوان، الملاحظات العامة، المهام المفتوحة، وآخر الزيارات. لا تخترع أي بيانات.",
    parametersJsonSchema: {
      type: "object",
      properties: { siteId: { type: "string", format: "uuid" } },
      required: ["siteId"],
    },
  },
  {
    name: "listOpenTasks",
    description: "هات المهام غير المكتملة لموقع محدد أو لكل المواقع المسموح بها.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        siteId: { type: "string", format: "uuid" },
        limit: { type: "integer", minimum: 1, maximum: 50 },
      },
      required: [],
    },
  },
  {
    name: "getVisitHistory",
    description: "هات سجل الزيارات لموقع محدد، مع إمكانية تحديد فترة تاريخية.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        siteId: { type: "string", format: "uuid" },
        from: dateOnly("من تاريخ"),
        to: dateOnly("إلى تاريخ"),
        limit: { type: "integer", minimum: 1, maximum: 50 },
      },
      required: ["siteId"],
    },
  },
  {
    name: "prepareVisitDraft",
    description:
      "جهّز مسودة زيارة للمراجعة فقط. لا تحفظ شيئاً. لازم تتأكد من الموقع والتاريخ والأرقام مع المستخدم قبل الحفظ.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        siteId: { type: "string", format: "uuid" },
        visitDate: dateOnly("تاريخ الزيارة"),
        completedWork: text("اللي خلص في الزيارة"),
        remainingWork: text("اللي لسه باقي في الموقع"),
        notes: text("ملاحظات إضافية"),
      },
      required: ["siteId", "completedWork"],
    },
  },
  {
    name: "prepareTaskDraft",
    description: "جهّز مسودة مهمة جديدة للمراجعة فقط. لا تحفظها.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        siteId: { type: "string", format: "uuid" },
        title: text("عنوان المهمة"),
        description: text("تفاصيل المهمة"),
        priority: { type: "string", enum: ["LOW", "NORMAL", "HIGH"] },
        dueDate: dateOnly("تاريخ الاستحقاق"),
      },
      required: ["title"],
    },
  },
  {
    name: "prepareTaskUpdate",
    description:
      "جهّز تعديل مقترح لمهمة موجودة (إكمال، إعادة فتح، تغيير أولوية...). لا تطبّق التعديل.",
    parametersJsonSchema: {
      type: "object",
      properties: {
        taskId: { type: "string", format: "uuid" },
        status: { type: "string", enum: ["OPEN", "IN_PROGRESS", "DONE"] },
        title: text("عنوان جديد"),
        description: text("وصف جديد"),
        priority: { type: "string", enum: ["LOW", "NORMAL", "HIGH"] },
        dueDate: dateOnly("تاريخ استحقاق جديد"),
      },
      required: ["taskId"],
    },
  },
];

export function buildSystemInstruction(userName: string, today = todayInCairo()): string {
  return [
    "أنت «مساعد المواقع»، مساعد ميداني بيتكلم مصري طبيعي وبسيط.",
    `اسم المستخدم: ${userName}. النهارده عندنا في القاهرة: ${today} (توقيت ${CAIRO_TIME_ZONE}).`,
    "",
    "قواعد صارمة:",
    "1. أي معلومة عن موقع أو مهمة أو زيارة أو تاريخ أو رقم لازم تيجي من الأدوات. ممنوع تخترع أسماء أو أرقام أو تواريخ.",
    "2. لو الموقع مش واضح أو في أكتر من احتمال، اسأل سؤال واحد قصير: «تقصد أنهي موقع؟».",
    "3. لو رقم أو تاريخ حساس مش متأكد منه، اقرأه للمستخدم قبل ما تجهز المسودة.",
    "4. أي إضافة أو تعديل لازم يكون مسودة أولاً (prepareVisitDraft / prepareTaskDraft / prepareTaskUpdate)، وبعدها اقرأ ملخص قصير واسأل: «أأكد الحفظ؟».",
    "5. ممنوع تقول إنك حفظت أو عدّلت. الحفظ بيحصل من المستخدم من شاشة المراجعة بعد التأكيد.",
    "6. لو المستخدم سأل سؤال، جاوب من البيانات المسجلة بس، واذكر إن اللي متبقي هو المهام المفتوحة حالياً.",
    "7. الزيارة سجل تاريخي مستقل. متعدلش زيارة قديمة عشان حالة مهمة اتغيرت.",
    "8. مفيش أي كلام عن أسعار أو تكاليف أو أرباح.",
    "9. خليك مختصر: جملتين أو تلاتة كحد أقصى، واسأل سؤال واحد بس في المرة.",
    "10. لو الشبكة أو الأدوات فشلت، قول للمستخدم يكمل يدوي، وما تدّعيش إن العملية تمت.",
    "",
    "طريقة الشغل:",
    "- لما المستخدم يذكر موقع، ابدأ بـ searchSites.",
    "- قبل أي مسودة زيارة، هات getSiteSummary عشان تعرف المهام المفتوحة الحالية.",
    "- فرّق بين «اللي خلص في الزيارة» و«اللي لسه متبقي» و«المهام المفتوحة».",
    "- لو المستخدم طلب مهمة جديدة، استخدم prepareTaskDraft. لو طلب إكمال مهمة، استخدم prepareTaskUpdate.",
    "",
    "اتكلم بالمصري الودود، من غير مبالغة ولا إيموجي.",
  ].join("\n");
}

export function buildLiveConfig(userName: string): LiveConnectConfig {
  return {
    responseModalities: [Modality.TEXT],
    temperature: 0.3,
    systemInstruction: { parts: [{ text: buildSystemInstruction(userName) }] },
    tools: [{ functionDeclarations: TOOL_DECLARATIONS }],
    sessionResumption: {},
    inputAudioTranscription: {},
    outputAudioTranscription: {},
  };
}

/** The exact setup payload the mobile client must send on the Live WebSocket. */
export function buildClientSetup(userName: string, modelId: string) {
  return {
    model: modelId.startsWith("models/") ? modelId : `models/${modelId}`,
    generationConfig: { responseModalities: ["TEXT"] },
    systemInstruction: { parts: [{ text: buildSystemInstruction(userName) }] },
    tools: [{ functionDeclarations: TOOL_DECLARATIONS }],
    sessionResumption: {},
    inputAudioTranscription: {},
    outputAudioTranscription: {},
  };
}
