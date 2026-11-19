String readableActionTitle(String action) {
  final map = {
    'ADMIN_ANALYTICS_WEEKLY_WORK_HOURS_ACCESSED': 'Weekly Work Hours Analytics Viewed',
    'ADMIN_ANALYTICS_FOCUS_RATE_ACCESSED': 'Focus Rate Analytics Viewed',
    'ADMIN_ANALYTICS_WEEKLY_FOCUS_IDLE_ACCESSED': 'Weekly Focus & Idle Analytics Viewed',
    'TEAM_VIEW_ACCESSED': 'Team View Accessed',
    'TEAM_CREATED': 'Team Created',
    'TEAM_UPDATED': 'Team Updated',
    'TEAM_DELETED': 'Team Deleted',
    'USER_CREATED': 'User Created',
    'USER_APPROVED': 'User Approved',
    'USER_REJECTED': 'User Rejected',
    'USER_UPDATED': 'User Updated',
    'USER_DELETED': 'User Deleted',
    'WORK_SESSION_STARTED': 'Work Session Started',
    'WORK_SESSION_ENDED': 'Work Session Ended',
    'TASK_CREATED': 'Task Created',
    'TASK_UPDATED': 'Task Updated',
    'TASK_COMPLETED': 'Task Completed',
    'BREAK_STARTED': 'Break Started',
    'BREAK_ENDED': 'Break Ended',
    'LOGIN': 'Login',
    'LOGOUT': 'Logout',
    'PASSWORD_RESET': 'Password Reset',
  };
  return map[action] ?? action.split('_').map((w) => w[0] + w.substring(1).toLowerCase()).join(' ');
}
