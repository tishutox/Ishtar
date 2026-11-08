import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icon names backed by the SVG files in `svg/`.
///
/// Each constant is the kebab-case file name without the `.svg` extension.
/// `AppIcon` renders the matching asset.
abstract final class AppIcons {
  static const accessibility = 'accessibility';
  static const arrowBigDownDash = 'arrow-big-down-dash';
  static const ban = 'ban';
  static const bell = 'bell';
  static const bolt = 'bolt';
  static const bookHeart = 'book-heart';
  static const bot = 'bot';
  static const cakeSlice = 'cake-slice';
  static const calendar = 'calendar';
  static const calendarRange = 'calendar-range';
  static const camera = 'camera';
  static const check = 'check';
  static const chevronDown = 'chevron-down';
  static const chevronLeft = 'chevron-left';
  static const chevronRight = 'chevron-right';
  static const circlePlus = 'circle-plus';
  static const circleUserRound = 'circle-user-round';
  static const compass = 'compass';
  static const cpu = 'cpu';
  static const download = 'download';
  static const earth = 'earth';
  static const equal = 'equal';
  static const eye = 'eye';
  static const eyeClosed = 'eye-closed';
  static const eyeOff = 'eye-closed';
  static const faceAngry = 'face-angry';
  static const faceExpressionless = 'face-expressionless';
  static const faceNeutral = 'face-neutral';
  static const faceSlightlyFrowning = 'face-slightly-frowning';
  static const faceSlightlySmiling = 'face-slightly-smiling';
  static const file = 'file';
  static const fingerprintPattern = 'fingerprint-pattern';
  static const headphones = 'headphones';
  static const headphoneOff = 'headphone-off';
  static const heart = 'heart';
  static const hourglass = 'hourglass';
  static const idCard = 'id-card';
  static const image = 'image';
  static const imageOff = 'image-off';
  static const imageUp = 'image-up';
  static const languages = 'languages';
  static const layoutGridCircles = 'layout-grid-circles';
  static const lifeBuoy = 'life-buoy';
  static const link = 'link';
  static const listFilter = 'list-filter';
  static const listX = 'list-x';
  static const loaderCircle = 'loader-circle';
  static const lock = 'lock';
  static const logIn = 'log-in';
  static const logOut = 'log-out';
  static const mail = 'mail';
  static const messageCircle = 'message-circle';
  static const messageCirclePlus = 'message-circle-plus';
  static const messageSquareText = 'message-square-text';
  static const messagesCircle = 'messages-circle';
  static const mic = 'mic';
  static const micOff = 'mic-off';
  static const pause = 'pause';
  static const pencil = 'pencil';
  static const pencilRuler = 'pencil-ruler';
  static const phone = 'phone';
  static const play = 'play';
  static const plus = 'plus';
  static const power = 'power';
  static const refreshCcw = 'refresh-ccw';
  static const reply = 'reply';
  static const save = 'save';
  static const search = 'search';
  static const send = 'send';
  static const sendHorizontal = 'send-horizontal';
  static const sticker = 'sticker';
  static const trash = 'trash';
  static const triangleAlert = 'triangle-alert';
  static const userMinus = 'user-round-minus';
  static const userPlus = 'user-round-plus';
  static const userRound = 'user-round';
  static const userX = 'user-round-x';
  static const usersRoundCollaboration = 'users-round-collaboration';
  static const video = 'video';
  static const videoOff = 'video-off';
  static const volume2 = 'volume-2';
  static const volumeOff = 'volume-off';
  static const x = 'x';
}

/// Renders an `svg/<name>.svg` asset as a recolourable icon.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.color, this.size});

  final String name;
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Colors.black;
    return SvgPicture.asset(
      'svg/$name.svg',
      width: size ?? 24,
      height: size ?? 24,
      colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
    );
  }
}
