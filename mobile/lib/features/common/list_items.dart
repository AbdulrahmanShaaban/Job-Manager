import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../models/site.dart';
import '../../models/task.dart';
import '../../models/visit.dart';
import 'ui.dart';

/// Reusable list rows shared by the dashboard, sites, tasks, and detail screens.

class SiteRow extends StatelessWidget {
  const SiteRow({
    super.key,
    required this.site,
    required this.onTap,
    this.showScope = false,
  });

  final Site site;
  final VoidCallback onTap;
  final bool showScope;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (showScope && site.scope == SiteScope.company && site.workspaceName != null)
        site.workspaceName!,
      if (site.address.isNotEmpty) site.address,
    ];

    return Semantics(
      button: true,
      label: '${site.name}، ${subtitleParts.join('، ')}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.scheme.muted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  site.scope == SiteScope.company ? LucideIcons.building2 : LucideIcons.userRound,
                  size: 19,
                  color: site.scope == SiteScope.company
                      ? context.scheme.primary
                      : context.mutedText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            site.name,
                            style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (site.pending) ...[const SizedBox(width: 6), const PendingTag()],
                        if (site.status == SiteStatus.archived) ...[
                          const SizedBox(width: 6),
                          Tag(label: 'مؤرشف', icon: LucideIcons.archive),
                        ],
                      ],
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitleParts.join(' • '),
                        style: context.texts.bodySmall?.copyWith(color: context.mutedText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (site.openTaskCount > 0)
                          Tag(
                            label: '${site.openTaskCount} مهمة مفتوحة',
                            icon: LucideIcons.checkSquare,
                            color: context.scheme.secondary,
                            foreground: context.scheme.secondaryForeground,
                            outline: false,
                          ),
                        if (site.lastVisit != null)
                          Text(
                            'آخر زيارة ${AppFormat.relativeDay(site.lastVisit!.visitDate)}',
                            style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                          )
                        else
                          Text(
                            'مفيش زيارات بعد',
                            style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronLeft, size: 16, color: context.mutedText),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    this.onTap,
    this.onToggle,
    this.showSite = true,
  });

  final Task task;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final bool showSite;

  @override
  Widget build(BuildContext context) {
    final done = task.status == TaskStatus.done;
    final overdue = task.isOverdue;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: done ? 'إعادة فتح المهمة' : 'إنهاء المهمة',
              child: ShadIconButton.ghost(
                width: 30,
                height: 30,
                padding: EdgeInsets.zero,
                onPressed: onToggle,
                icon: Icon(
                  done ? LucideIcons.circleCheck : LucideIcons.circleDot,
                  size: 20,
                  color: done ? context.scheme.primary : context.mutedText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.title,
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? context.mutedText : context.scheme.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (showSite && task.siteName != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.mapPin, size: 11, color: context.mutedText),
                            const SizedBox(width: 3),
                            Text(
                              task.siteName!,
                              style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                            ),
                          ],
                        ),
                      if (task.dueDate != null)
                        Text(
                          'مستحقة ${AppFormat.dayMonth(task.dueDate)}',
                          style: context.texts.labelSmall?.copyWith(
                            color: overdue ? context.scheme.destructive : context.mutedText,
                            fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      if (task.status == TaskStatus.inProgress)
                        Tag(
                          label: 'شغّال عليها',
                          color: context.scheme.secondary,
                          foreground: context.scheme.secondaryForeground,
                          outline: false,
                        ),
                      if (task.priority == TaskPriority.high)
                        Tag(
                          label: 'مهمة',
                          icon: LucideIcons.triangleAlert,
                          color: context.scheme.muted,
                          foreground: context.scheme.foreground,
                        ),
                      if (task.pending) const PendingTag(),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Icon(LucideIcons.chevronLeft, size: 16, color: context.mutedText),
              ),
          ],
        ),
      ),
    );
  }
}

class VisitRow extends StatelessWidget {
  const VisitRow({
    super.key,
    required this.visit,
    this.onTap,
    this.showSite = false,
  });

  final Visit visit;
  final VoidCallback? onTap;
  final bool showSite;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: context.scheme.muted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    AppFormat.dayMonth(visit.visitDate).split(' ').first,
                    style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    AppFormat.dayMonth(visit.visitDate).split(' ').skip(1).join(' '),
                    style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showSite && visit.siteName != null) ...[
                    Text(
                      visit.siteName!,
                      style: context.texts.labelSmall?.copyWith(
                        color: context.scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    visit.completedWork,
                    style: context.texts.bodyMedium?.copyWith(height: 1.45),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (visit.createdByName != null)
                        Text(
                          visit.createdByName!,
                          style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                        ),
                      if (visit.isVoice)
                        Tag(label: 'بالصوت', icon: LucideIcons.mic, color: context.scheme.muted),
                      if (visit.wasEdited)
                        Tag(label: 'اتعدّلت', icon: LucideIcons.pencil, color: context.scheme.muted),
                      if (visit.pending) const PendingTag(),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(LucideIcons.chevronLeft, size: 16, color: context.mutedText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
