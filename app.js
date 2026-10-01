const STORAGE_KEY = 'strivo-coach-workspace-v1';

const starterData = {
  students: [
    { id: 's1', name: 'Mira Kapoor', group: 'U12 · Foundations', joined: '2026-07-12' },
    { id: 's2', name: 'Kabir Shah', group: 'U12 · Foundations', joined: '2026-08-03' },
    { id: 's3', name: 'Anaya Rao', group: 'U14 · Performance', joined: '2026-06-21' },
    { id: 's4', name: 'Arjun Nair', group: 'U14 · Performance', joined: '2026-08-14' },
    { id: 's5', name: 'Diya Menon', group: 'U10 · Starters', joined: '2026-09-02' },
    { id: 's6', name: 'Ishaan Das', group: 'U10 · Starters', joined: '2026-09-08' },
  ],
  classes: [
    { id: 'c1', name: 'U12 · Foundations', day: 'Monday, Wednesday', time: '4:00 PM', coach: 'Aisha Mehta', studentIds: ['s1', 's2'] },
    { id: 'c2', name: 'U14 · Performance', day: 'Tuesday, Thursday', time: '5:30 PM', coach: 'Aisha Mehta', studentIds: ['s3', 's4'] },
    { id: 'c3', name: 'U10 · Starters', day: 'Saturday', time: '9:00 AM', coach: 'Aisha Mehta', studentIds: ['s5', 's6'] },
  ],
  skills: [
    { id: 'k1', name: 'Ball control', category: 'Movement', scale: '5-point scale' },
    { id: 'k2', name: 'Passing accuracy', category: 'Technique', scale: '5-point scale' },
    { id: 'k3', name: 'Spatial awareness', category: 'Game sense', scale: '5-point scale' },
    { id: 'k4', name: 'First touch', category: 'Technique', scale: '5-point scale' },
    { id: 'k5', name: 'Agility', category: 'Movement', scale: '5-point scale' },
    { id: 'k6', name: 'Team communication', category: 'Game sense', scale: '5-point scale' },
  ],
  assessments: [
    { id: 'a1', studentId: 's1', skillId: 'k1', score: 4, note: 'More confident changing direction.', date: '2026-09-29' },
    { id: 'a2', studentId: 's2', skillId: 'k2', score: 3, note: 'Keep the follow-through relaxed.', date: '2026-09-29' },
    { id: 'a3', studentId: 's3', skillId: 'k3', score: 4, note: 'Good scanning before receiving.', date: '2026-09-28' },
    { id: 'a4', studentId: 's4', skillId: 'k4', score: 3, note: 'Try cushioning with the inside of the foot.', date: '2026-09-27' },
    { id: 'a5', studentId: 's5', skillId: 'k5', score: 3, note: 'Quick feet are improving.', date: '2026-09-26' },
    { id: 'a6', studentId: 's1', skillId: 'k2', score: 3, note: 'Accurate over short distances.', date: '2026-09-22' },
    { id: 'a7', studentId: 's3', skillId: 'k1', score: 4, note: 'Strong control under pressure.', date: '2026-09-20' },
  ],
  attendance: {},
};

function loadData() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) return { ...structuredClone(starterData), ...JSON.parse(saved) };
  } catch (error) {
    console.warn('Strivo could not read saved workspace data.', error);
  }
  return structuredClone(starterData);
}

let data = loadData();
let currentView = 'overview';
let toastTimer;

const page = document.querySelector('#page-content');
const modal = document.querySelector('#app-modal');
const form = document.querySelector('#modal-form');
const modalFields = document.querySelector('#modal-fields');

const today = new Date();
const localDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
const weekStartDate = new Date(today);
weekStartDate.setDate(today.getDate() - 6);
const weekStart = `${weekStartDate.getFullYear()}-${String(weekStartDate.getMonth() + 1).padStart(2, '0')}-${String(weekStartDate.getDate()).padStart(2, '0')}`;
document.querySelector('#today-label').textContent = today.toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });

function persist() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  } catch (error) {
    notify('Could not save on this device.');
    console.warn('Strivo could not save workspace data.', error);
  }
}

function escapeHtml(value = '') {
  return String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

function initials(name) {
  return name.split(/\s+/).map((part) => part[0]).slice(0, 2).join('').toUpperCase();
}

function person(id) { return data.students.find((student) => student.id === id); }
function skill(id) { return data.skills.find((item) => item.id === id); }
function prettyDate(value) {
  if (!value) return '—';
  return new Date(`${value}T12:00:00`).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
}
function allScores(studentId, skillId) {
  return data.assessments.filter((item) => (!studentId || item.studentId === studentId) && (!skillId || item.skillId === skillId));
}
function average(items) {
  return items.length ? items.reduce((sum, item) => sum + Number(item.score), 0) / items.length : 0;
}
function studentProgress(studentId) {
  const scores = allScores(studentId);
  return scores.length ? Math.round((average(scores) / 5) * 100) : 0;
}
function initialsClass(index) { return ['pink', 'blue', 'yellow', 'green'][index % 4]; }

function heading(title, description, eyebrow = 'COACH WORKSPACE', action = '') {
  return `<div class="page-heading"><div><div class="eyebrow">${eyebrow}</div><h1>${title}</h1><p>${description}</p></div>${action ? `<div>${action}</div>` : ''}</div>`;
}

function metric(label, value, note, change = '') {
  return `<div class="metric"><div class="metric-label">${label}</div><div class="metric-main"><span class="metric-value">${value}</span>${change ? `<span class="metric-change">${change}</span>` : ''}</div><div class="metric-foot">${note}</div></div>`;
}

function studentNameCell(student, index) {
  return `<div class="student-cell"><span class="avatar ${initialsClass(index)}">${escapeHtml(initials(student.name))}</span><span class="student-name">${escapeHtml(student.name)}</span></div>`;
}

function recentAssessmentRows(limit = 5) {
  return [...data.assessments].sort((a, b) => b.date.localeCompare(a.date)).slice(0, limit).map((assessment, index) => {
    const student = person(assessment.studentId);
    const matchedSkill = skill(assessment.skillId);
    if (!student || !matchedSkill) return '';
    return `<tr><td>${studentNameCell(student, index)}</td><td>${escapeHtml(matchedSkill.name)}</td><td><span class="record-score">${assessment.score}</span><span class="subtle"> / 5</span></td><td>${prettyDate(assessment.date)}</td><td><span class="pill">Recorded</span></td></tr>`;
  }).join('');
}

function renderOverview() {
  const todayAttendance = data.students.filter((student) => data.attendance[`${localDate}:${student.id}`] === 'present').length;
  const attendanceRate = data.students.length ? Math.round((todayAttendance / data.students.length) * 100) : 0;
  const newAssessments = data.assessments.filter((item) => item.date >= weekStart).length;
  const topStudents = [...data.students].sort((a, b) => studentProgress(b.id) - studentProgress(a.id)).slice(0, 5);
  const classSummaries = data.classes.slice(0, 3).map((item) => `<div class="class-summary"><span>${escapeHtml(item.day)} · ${escapeHtml(item.time)}</span><strong>${escapeHtml(item.name)}</strong><small>${item.studentIds.filter((id) => person(id)).length} students · ${escapeHtml(item.coach)}</small></div>`).join('');
  const activityItems = [...data.assessments].sort((a, b) => b.date.localeCompare(a.date)).slice(0, 4).map((item) => {
    const student = person(item.studentId);
    const matchedSkill = skill(item.skillId);
    if (!student || !matchedSkill) return '';
    return `<div class="activity-item"><span class="activity-mark">↗</span><div class="activity-copy"><span><strong>${escapeHtml(student.name)}</strong> · ${escapeHtml(matchedSkill.name)}</span><span class="subtle">Coach rating ${item.score} of 5</span></div><span class="activity-time">${prettyDate(item.date)}</span></div>`;
  }).join('');

  return `${heading('Good morning, Aisha', 'A clear view of the people, practice and progress in your studio.', today.toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' }).toUpperCase())}
    <section class="metric-grid" aria-label="Studio summary">
      ${metric('ACTIVE STUDENTS', data.students.length, 'Across your coaching groups', '+2 this month')}
      ${metric('ACTIVE CLASSES', data.classes.length, 'Your current weekly schedule')}
      ${metric('ASSESSMENTS', newAssessments, 'Skill check-ins this week')}
      ${metric('ATTENDANCE TODAY', `${attendanceRate}%`, `${todayAttendance} of ${data.students.length} marked present`)}
    </section>
    <section class="content-grid">
      <div class="panel"><div class="panel-header"><h2>Student progress</h2><button class="text-button" data-go="progress">View all progress →</button></div>
        ${topStudents.length ? `<div class="table-wrap"><table><thead><tr><th>STUDENT</th><th>CLASS</th><th>SKILL PROGRESS</th><th>LAST CHECK-IN</th></tr></thead><tbody>${topStudents.map((student, index) => {
          const latest = [...allScores(student.id)].sort((a, b) => b.date.localeCompare(a.date))[0];
          const group = data.classes.find((item) => item.studentIds.includes(student.id))?.name || student.group;
          const progress = studentProgress(student.id);
          return `<tr><td>${studentNameCell(student, index)}</td><td>${escapeHtml(group)}</td><td><div class="progress-cell"><div class="progress-track"><div class="progress-fill" style="width:${progress}%"></div></div><span class="progress-number">${progress}%</span></div></td><td>${prettyDate(latest?.date)}</td></tr>`;
        }).join('')}</tbody></table></div>` : '<div class="empty-state">Add students to start tracking progress.</div>'}
      </div>
      <div class="panel"><div class="panel-header"><h2>Recent coach notes</h2><button class="text-button" data-go="assessments">All assessments →</button></div><div class="activity-list">${activityItems || '<div class="empty-state">Your latest assessments will show here.</div>'}</div></div>
    </section>
    <section class="panel" style="margin-top:16px"><div class="panel-header"><h2>Upcoming classes</h2><button class="text-button" data-go="classes">Manage classes →</button></div><div class="class-strip">${classSummaries || '<div class="empty-state">Create a class to build your weekly schedule.</div>'}</div></section>`;
}

function renderStudents() {
  const action = '<button class="button button-primary" data-action="add-student"><span>＋</span> Add student</button>';
  return `${heading('Students', 'Keep each learner’s development connected to their coaching group.', 'PEOPLE · LEARNERS', action)}
    <div class="toolbar"><label class="search-box"><input id="student-search" type="search" placeholder="Search students" aria-label="Search students" /></label><select class="select-control" id="student-class-filter" aria-label="Filter by class"><option value="">All classes</option>${data.classes.map((item) => `<option value="${escapeHtml(item.name)}">${escapeHtml(item.name)}</option>`).join('')}</select><span class="spacer"></span><span class="heading-aside">${data.students.length} students</span></div>
    <div class="table-panel"><div class="table-wrap"><table><thead><tr><th>STUDENT</th><th>COACHING GROUP</th><th>SKILL PROGRESS</th><th>LAST ASSESSMENT</th><th>JOINED</th></tr></thead><tbody id="students-body">${studentRows(data.students)}</tbody></table></div></div>`;
}

function studentRows(students) {
  if (!students.length) return '<tr><td colspan="5"><div class="empty-state">No students match this view.</div></td></tr>';
  return students.map((student, index) => {
    const latest = [...allScores(student.id)].sort((a, b) => b.date.localeCompare(a.date))[0];
    return `<tr><td>${studentNameCell(student, index)}</td><td>${escapeHtml(student.group)}</td><td><div class="progress-cell"><div class="progress-track"><div class="progress-fill" style="width:${studentProgress(student.id)}%"></div></div><span class="progress-number">${studentProgress(student.id)}%</span></div></td><td>${prettyDate(latest?.date)}</td><td>${prettyDate(student.joined)}</td></tr>`;
  }).join('');
}

function renderClasses() {
  const action = '<button class="button button-primary" data-action="add-class"><span>＋</span> Create class</button>';
  const rows = data.classes.map((item) => `<tr><td><span class="student-name">${escapeHtml(item.name)}</span></td><td>${escapeHtml(item.day)}</td><td>${escapeHtml(item.time)}</td><td>${escapeHtml(item.coach)}</td><td>${item.studentIds.filter((id) => person(id)).length} students</td><td><span class="pill">Active</span></td></tr>`).join('');
  return `${heading('Classes', 'Organize coaching groups and keep every session connected to progress.', 'STUDIO · SCHEDULE', action)}<div class="table-panel"><div class="table-wrap"><table><thead><tr><th>CLASS</th><th>DAYS</th><th>TIME</th><th>COACH</th><th>ROSTER</th><th>STATUS</th></tr></thead><tbody>${rows || '<tr><td colspan="6"><div class="empty-state">No classes yet. Create your first coaching group.</div></td></tr>'}</tbody></table></div></div>`;
}

function renderSkills() {
  const action = '<button class="button button-primary" data-action="add-skill"><span>＋</span> Add skill</button>';
  const skillItems = data.skills.map((item) => {
    const scores = allScores(null, item.id);
    const score = average(scores);
    return `<div class="skill-row"><div><div class="skill-title">${escapeHtml(item.name)}</div><div class="skill-meta">${escapeHtml(item.category)} · ${scores.length} assessments</div></div><div class="skill-score">${score ? score.toFixed(1) : '—'}<small> / 5</small></div><div class="skill-progress"><span style="width:${score ? (score / 5) * 100 : 0}%"></span></div></div>`;
  }).join('');
  return `${heading('Skills', 'The capabilities your coaches observe, practice and assess.', 'DEVELOPMENT · SKILL LIBRARY', action)}<div class="panel"><div class="panel-header"><h2>Skill library</h2><span class="heading-aside">${data.skills.length} skills · 5-point scale</span></div><div class="skill-list">${skillItems || '<div class="empty-state">Add skills to define what development looks like.</div>'}</div></div>`;
}

function renderAssessments() {
  const action = '<button class="button button-primary" data-action="add-assessment"><span>＋</span> Record assessment</button>';
  const rows = [...data.assessments].sort((a, b) => b.date.localeCompare(a.date)).map((item) => {
    const student = person(item.studentId);
    const matchedSkill = skill(item.skillId);
    if (!student || !matchedSkill) return '';
    return `<tr><td>${escapeHtml(prettyDate(item.date))}</td><td><span class="student-name">${escapeHtml(student.name)}</span></td><td>${escapeHtml(matchedSkill.name)}</td><td><span class="record-score">${item.score}</span><span class="subtle"> / 5</span></td><td><span class="record-detail">${escapeHtml(item.note || 'No coach note')}</span></td></tr>`;
  }).join('');
  return `${heading('Assessments', 'Record observable skill development and leave a useful note for the next session.', 'DEVELOPMENT · COACH CHECK-INS', action)}<div class="notice" style="margin-bottom:14px">Use a consistent 1–5 rating and a short, specific observation. These coach records build each student’s progress history.</div><div class="table-panel"><div class="table-wrap"><table><thead><tr><th>DATE</th><th>STUDENT</th><th>SKILL</th><th>RATING</th><th>COACH NOTE</th></tr></thead><tbody>${rows || '<tr><td colspan="5"><div class="empty-state">No assessments yet. Record a skill check-in to start a progress history.</div></td></tr>'}</tbody></table></div></div>`;
}

function renderProgress() {
  const rows = data.students.map((student, index) => {
    const scores = allScores(student.id);
    const last = [...scores].sort((a, b) => b.date.localeCompare(a.date))[0];
    const observed = new Set(scores.map((item) => item.skillId)).size;
    return `<tr><td>${studentNameCell(student, index)}</td><td>${escapeHtml(student.group)}</td><td><div class="progress-cell"><div class="progress-track"><div class="progress-fill" style="width:${studentProgress(student.id)}%"></div></div><span class="progress-number">${studentProgress(student.id)}%</span></div></td><td>${observed} of ${data.skills.length} skills</td><td>${scores.length}</td><td>${prettyDate(last?.date)}</td></tr>`;
  }).join('');
  return `${heading('Progress', 'Compare skill development across students, built from coach assessments.', 'DEVELOPMENT · STUDENT PROGRESS')}<div class="notice" style="margin-bottom:14px">Progress score is the average of recorded 1–5 skill ratings, shown as a percentage. It is a coaching aid, not a student ranking.</div><div class="table-panel"><div class="table-wrap"><table><thead><tr><th>STUDENT</th><th>COACHING GROUP</th><th>OVERALL PROGRESS</th><th>SKILLS OBSERVED</th><th>CHECK-INS</th><th>LAST CHECK-IN</th></tr></thead><tbody>${rows || '<tr><td colspan="6"><div class="empty-state">Add students and assessments to see progress.</div></td></tr>'}</tbody></table></div></div>`;
}

function attendanceStatus(student) {
  return data.attendance[`${localDate}:${student.id}`] || 'unmarked';
}

function renderAttendance() {
  const present = data.students.filter((student) => attendanceStatus(student) === 'present').length;
  const marked = data.students.filter((student) => attendanceStatus(student) !== 'unmarked').length;
  const rate = marked ? Math.round((present / marked) * 100) : 0;
  const rows = data.students.map((student, index) => {
    const status = attendanceStatus(student);
    const group = data.classes.find((item) => item.studentIds.includes(student.id))?.name || student.group;
    const buttonText = status === 'present' ? '✓' : status === 'absent' ? '×' : '·';
    return `<tr><td>${studentNameCell(student, index)}</td><td>${escapeHtml(group)}</td><td>${status === 'unmarked' ? '<span class="pill gray">Not marked</span>' : status === 'present' ? '<span class="pill">Present</span>' : '<span class="pill coral">Absent</span>'}</td><td><button class="check-button ${status}" data-attendance="${student.id}" aria-label="Change attendance for ${escapeHtml(student.name)}">${buttonText}</button></td></tr>`;
  }).join('');
  return `${heading('Attendance', 'A simple session register for knowing who was in practice.', 'STUDIO · SESSION REGISTER')}<div class="table-panel"><div class="attendance-summary"><div class="attendance-rate">${rate}%</div><div class="attendance-caption"><strong>${present} present · ${marked} marked</strong><span>Today’s register · ${prettyDate(localDate)}</span></div><div class="attendance-date">${today.toLocaleDateString('en-IN', { weekday: 'long' })}</div></div><div class="table-wrap"><table><thead><tr><th>STUDENT</th><th>COACHING GROUP</th><th>STATUS</th><th>MARK ATTENDANCE</th></tr></thead><tbody>${rows || '<tr><td colspan="4"><div class="empty-state">Add students to begin taking attendance.</div></td></tr>'}</tbody></table></div></div>`;
}

const renderers = { overview: renderOverview, classes: renderClasses, students: renderStudents, skills: renderSkills, assessments: renderAssessments, progress: renderProgress, attendance: renderAttendance };
const titles = { overview: 'Overview', classes: 'Classes', students: 'Students', skills: 'Skills', assessments: 'Assessments', progress: 'Progress', attendance: 'Attendance' };

function render() {
  document.querySelector('#current-section').textContent = titles[currentView];
  document.querySelectorAll('.nav-link').forEach((link) => {
    const active = link.dataset.view === currentView;
    link.classList.toggle('active', active);
    link.setAttribute('aria-current', active ? 'page' : 'false');
  });
  page.innerHTML = renderers[currentView]();
}

function notify(message) {
  const toast = document.querySelector('#toast');
  toast.textContent = message;
  toast.classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('visible'), 2500);
}

function field(name, label, type = 'text', options = {}) {
  const required = options.required === false ? '' : 'required';
  const value = options.value ? ` value="${escapeHtml(options.value)}"` : '';
  if (type === 'select') {
    return `<div class="field"><label for="field-${name}">${label}</label><select class="field-control" id="field-${name}" name="${name}" ${required}>${options.placeholder ? `<option value="">${options.placeholder}</option>` : ''}${(options.choices || []).map((choice) => `<option value="${escapeHtml(choice.value)}">${escapeHtml(choice.label)}</option>`).join('')}</select></div>`;
  }
  if (type === 'textarea') return `<div class="field"><label for="field-${name}">${label}</label><textarea class="field-control" id="field-${name}" name="${name}" ${required} placeholder="${escapeHtml(options.placeholder || '')}"></textarea></div>`;
  return `<div class="field"><label for="field-${name}">${label}</label><input class="field-control" id="field-${name}" name="${name}" type="${type}"${value} ${required} ${options.min ? `min="${options.min}"` : ''} ${options.max ? `max="${options.max}"` : ''} placeholder="${escapeHtml(options.placeholder || '')}" /></div>`;
}

function openForm(type) {
  const configs = {
    student: { title: 'Add student', button: 'Add student', fields: `${field('name', 'Student name', 'text', { placeholder: 'Full name' })}${field('group', 'Coaching group', 'select', { placeholder: 'Choose a class', choices: data.classes.map((item) => ({ value: item.name, label: item.name })) })}${field('joined', 'Start date', 'date', { value: localDate })}` },
    class: { title: 'Create class', button: 'Create class', fields: `${field('name', 'Class name', 'text', { placeholder: 'e.g. U12 · Foundations' })}${field('day', 'Training days', 'text', { placeholder: 'e.g. Monday, Wednesday' })}${field('time', 'Session time', 'text', { placeholder: 'e.g. 4:00 PM' })}${field('coach', 'Coach', 'text', { value: 'Aisha Mehta' })}` },
    skill: { title: 'Add skill', button: 'Add skill', fields: `${field('name', 'Skill name', 'text', { placeholder: 'e.g. Balance' })}${field('category', 'Category', 'select', { placeholder: 'Choose a category', choices: ['Movement', 'Technique', 'Game sense', 'Fitness', 'Other'].map((value) => ({ value, label: value })) })}` },
    assessment: { title: 'Record assessment', button: 'Save assessment', fields: `${field('studentId', 'Student', 'select', { placeholder: 'Choose a student', choices: data.students.map((item) => ({ value: item.id, label: item.name })) })}${field('skillId', 'Skill', 'select', { placeholder: 'Choose a skill', choices: data.skills.map((item) => ({ value: item.id, label: `${item.name} · ${item.category}` })) })}${field('score', 'Coach rating · 1 to 5', 'number', { min: 1, max: 5, placeholder: '0-5' })}${field('note', 'Coach observation', 'textarea', { required: false, placeholder: 'What did you observe? What should they practice next?' })}${field('date', 'Assessment date', 'date', { value: localDate })}` },
  };
  const config = configs[type];
  form.dataset.type = type;
  document.querySelector('#modal-title').textContent = config.title;
  document.querySelector('#save-record').textContent = config.button;
  modalFields.innerHTML = config.fields;
  modal.showModal();
  modalFields.querySelector('input, select')?.focus();
}

function saveForm(event) {
  event.preventDefault();
  const values = Object.fromEntries(new FormData(form).entries());
  const id = `${form.dataset.type[0]}${Date.now()}`;
  if (form.dataset.type === 'student') {
    if (!values.group) { notify('Create a class first, then add students.'); return; }
    data.students.unshift({ id, name: values.name.trim(), group: values.group, joined: values.joined });
    const selectedClass = data.classes.find((item) => item.name === values.group);
    if (selectedClass) selectedClass.studentIds.push(id);
  }
  if (form.dataset.type === 'class') {
    data.classes.push({ id, name: values.name.trim(), day: values.day.trim(), time: values.time.trim(), coach: values.coach.trim(), studentIds: [] });
  }
  if (form.dataset.type === 'skill') {
    data.skills.push({ id, name: values.name.trim(), category: values.category, scale: '5-point scale' });
  }
  if (form.dataset.type === 'assessment') {
    data.assessments.unshift({ id, studentId: values.studentId, skillId: values.skillId, score: Number(values.score), note: values.note.trim(), date: values.date });
  }
  persist();
  modal.close();
  render();
  notify(`${document.querySelector('#modal-title').textContent.replace('Add ', '').replace('Create ', '')} saved.`);
}

document.querySelectorAll('.nav-link').forEach((link) => link.addEventListener('click', () => {
  currentView = link.dataset.view;
  render();
}));

document.querySelector('#quick-assessment').addEventListener('click', () => openForm('assessment'));
document.querySelector('#close-modal').addEventListener('click', () => modal.close());
document.querySelector('#cancel-modal').addEventListener('click', () => modal.close());
form.addEventListener('submit', saveForm);

page.addEventListener('click', (event) => {
  const button = event.target.closest('[data-action], [data-go], [data-attendance]');
  if (!button) return;
  if (button.dataset.action) openForm(button.dataset.action.replace('add-', ''));
  if (button.dataset.go) {
    currentView = button.dataset.go;
    render();
  }
  if (button.dataset.attendance) {
    const key = `${localDate}:${button.dataset.attendance}`;
    const current = data.attendance[key] || 'unmarked';
    data.attendance[key] = current === 'unmarked' ? 'present' : current === 'present' ? 'absent' : 'unmarked';
    persist();
    render();
  }
});

page.addEventListener('input', (event) => {
  if (event.target.id !== 'student-search') return;
  const term = event.target.value.trim().toLowerCase();
  const classFilter = document.querySelector('#student-class-filter')?.value || '';
  const students = data.students.filter((student) => student.name.toLowerCase().includes(term) && (!classFilter || student.group === classFilter));
  document.querySelector('#students-body').innerHTML = studentRows(students);
});

page.addEventListener('change', (event) => {
  if (event.target.id !== 'student-class-filter') return;
  const search = document.querySelector('#student-search')?.value.trim().toLowerCase() || '';
  const students = data.students.filter((student) => student.name.toLowerCase().includes(search) && (!event.target.value || student.group === event.target.value));
  document.querySelector('#students-body').innerHTML = studentRows(students);
});

render();