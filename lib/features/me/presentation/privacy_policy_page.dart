import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';

/// Full text of the privacy policy, opened from Settings → Data Privacy &
/// Safety → Privacy Policy.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
        title: const Text('Privacy Policy'),
      ),
      body: ListView(
        padding: ContentLayout.pagePadding,
        children: [
          ContentLayout.widthBox(
            child: const Text(
              'Last updated: November 12, 2026',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '1. Overview',
              children: [
                _Paragraph(
                  'Ishtar is an AI companion. This policy explains what data '
                  'we collect, how we use it, and the choices you have. Our '
                  'guiding principle is to collect only what is needed to '
                  'provide the service.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '2. Data we collect',
              children: [
                _Paragraph(
                  'Account information. When you create an account we store '
                  'your email address, username, display name, and any profile '
                  'image or banner you set. Your password is handled by our '
                  'authentication provider and is never visible to us.',
                ),
                _Paragraph(
                  'Your conversations. Your chats with Ishtar — including text, '
                  'images and files you attach — are stored '
                  'only on your device. They are not uploaded to our servers '
                  'and are not synced across devices.',
                ),
                _Paragraph(
                  'Settings. We store a small amount of preference data, such '
                  'as your chosen AI response style and whether the AI is '
                  'allowed to keep memories between chats.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '3. How we use your data',
              children: [
                _Paragraph(
                  'We use your account information to sign you in, identify '
                  'your account, and let you manage your profile. We use your '
                  'preferences to remember how you like Ishtar to respond. '
                  'We do not sell your personal data and we do not use your '
                  'conversations to build advertising profiles.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '4. AI processing',
              children: [
                _Paragraph(
                  'To generate a reply, the text of your message is sent to a '
                  'third-party AI model. Depending on availability this is '
                  'either a hosted model or a public, keyless AI endpoint. The '
                  'providers receive only the messages needed to produce a '
                  'reply and are bound by their own privacy terms.',
                ),
                _Paragraph(
                  'You can switch to the on-device model from the chat screen. '
                  'When the on-device model is active, your messages are '
                  'processed entirely on your device and are not sent to any '
                  'AI provider.',
                ),
                _Paragraph(
                  'Voice input. When you dictate a message with the '
                  'microphone, your speech is transcribed by your device\'s '
                  'speech-recognition service (Google on Android, Apple on '
                  'iOS). Depending on the service, the audio may be processed '
                  'in the cloud by that provider under its own privacy policy. '
                  'Only the resulting text is then sent as a normal message.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '5. Storage and retention',
              children: [
                _Paragraph(
                  'Conversations remain on your device until you delete a chat '
                  'or remove the app. Account information is kept while your '
                  'account exists and is removed when you delete your account.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '6. Third-party services',
              children: [
                _Paragraph(
                  'We rely on a small number of service providers: an '
                  'authentication and database provider for accounts, and AI '
                  'providers for generating replies. Each provider processes '
                  'data under their own privacy policies and only receives '
                  'what is necessary for its function.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '7. Your choices',
              children: [
                _Paragraph(
                  'You can edit or delete your profile information at any time '
                  'from Settings. You can disable the “Keep Memories” option '
                  'under Settings → Data Privacy & Safety so the AI does not '
                  'carry context between chats. You can delete individual '
                  'chats from the dashboard.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '8. Deleting your data',
              children: [
                _Paragraph(
                  'You can delete your account at any time from Settings → '
                  'Account → Danger Zone → Delete Account. Deleting your '
                  'account removes your account information from our systems. '
                  'To remove your conversations, delete them in the app or '
                  'uninstall the app, which clears on-device data.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '9. Children’s privacy',
              children: [
                _Paragraph(
                  'Ishtar is not intended for children. We do not knowingly '
                  'collect personal information from children under the age '
                  'of 18. If you believe a child has provided us with personal '
                  'data, contact us and we will delete it.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '10. Changes to this policy',
              children: [
                _Paragraph(
                  'We may update this policy from time to time. When we make '
                  'meaningful changes, we will update the “Last updated” date '
                  'at the top of this page. Continued use of the app after a '
                  'change means you accept the updated policy.',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const _PolicySection(
              title: '11. Contact',
              children: [
                _Paragraph(
                  'If you have questions about this policy or about how your '
                  'data is handled, you can reach us through the support '
                  'channels listed in Settings → Support Us.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF1A1A1A),
          fontSize: 15,
          height: 1.45,
        ),
      ),
    );
  }
}
