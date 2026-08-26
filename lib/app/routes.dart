import 'package:flutter/material.dart';

import '../core/services/image_service.dart';
import '../data/models.dart';
import '../features/auth/login_page.dart';
import '../features/children/child_setup_page.dart';
import '../features/classwork/add_classwork_page.dart';
import '../features/classwork/classwork_detail_page.dart';
import '../features/exam/add_exam_page.dart';
import '../features/exam/exam_detail_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/onboarding/splash_page.dart';
import '../features/picker/picker_page.dart';
import '../features/settings/add_subject_page.dart';
import '../features/settings/add_year_page.dart';
import '../features/share/attach_answer_key_page.dart';
import '../features/share/share_chooser_page.dart';
import '../features/share/share_image_page.dart';
import '../features/viewer/viewer_page.dart';
import '../features/worksheet/add_worksheet_page.dart';
import '../features/worksheet/worksheet_detail_page.dart';
import '../shell/main_shell.dart';

/// Routes that cover the whole screen and hide the bottom navigation — the
/// design's `chromeless` list. Tab-local destinations live in [MainShell].
abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const childSetup = '/child-setup';
  static const shell = '/shell';
  static const addWorksheet = '/add-worksheet';
  static const worksheetDetail = '/worksheet';
  static const addClasswork = '/add-classwork';
  static const classworkDetail = '/classwork';
  static const addExam = '/add-exam';
  static const examDetail = '/exam';
  static const shareChooser = '/share-chooser';
  static const shareImage = '/share-image';
  static const attachAnswerKey = '/attach-answer-key';
  static const picker = '/picker';
  static const viewer = '/viewer';
  static const addSubject = '/add-subject';
  static const addYear = '/add-year';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    Route<T> page<T>(Widget child) =>
        MaterialPageRoute<T>(builder: (_) => child, settings: settings);

    switch (settings.name) {
      case splash:
        return page(const SplashPage());
      case onboarding:
        return page(const OnboardingPage());
      case login:
        return page(const LoginPage());
      case childSetup:
        return page(ChildSetupPage(child: settings.arguments as Child?));
      case shell:
        return page(const MainShell());
      case addWorksheet:
        return page(AddWorksheetPage(existing: settings.arguments as DiaryRecord?));
      case worksheetDetail:
        return page(WorksheetDetailPage(recordId: settings.arguments! as String));
      case addClasswork:
        return page(AddClassworkPage(existing: settings.arguments as DiaryRecord?));
      case classworkDetail:
        return page(ClassworkDetailPage(recordId: settings.arguments! as String));
      case addExam:
        return page(AddExamPage(existing: settings.arguments as DiaryRecord?));
      case examDetail:
        return page(ExamDetailPage(recordId: settings.arguments! as String));
      case shareChooser:
        return page(
          ShareChooserPage(args: settings.arguments! as ShareImageArgs),
        );
      case shareImage:
        return page(
          ShareImagePage(args: settings.arguments as ShareImageArgs?),
        );
      case attachAnswerKey:
        return page(
          AttachAnswerKeyPage(file: settings.arguments! as PickedAttachment),
        );
      case picker:
        return page(const PickerPage());
      case viewer:
        return page(ViewerPage(args: settings.arguments! as ViewerArgs));
      case addSubject:
        return page(const AddSubjectPage());
      case addYear:
        return page(const AddYearPage());
      default:
        return null;
    }
  }
}
