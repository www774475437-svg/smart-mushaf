import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../data/surah_names.dart';
import '../services/audio.dart';
import 'common.dart';

const String kMukhtasarAudioName = 'المختصر الصوتي';
const String kMukhtasarAudioBy = 'عبدالله الأسمري وصابر عبدالحكم';

/// The recorded «المختصر في تفسير القرآن الكريم» (مركز تفسير): the ayahs are recited
/// by صابر عبدالحكم and their tafsir is read by عبدالله الأسمري. One recording per surah.
String mukhtasarAudioUrl(int s) =>
    'https://d1.islamhouse.com/data/ar/ih_sounds/chain_01/mokhtasar-fe-tafceer/ar-${s.toString().padLeft(3, '0')}-mokhtasar-fe-tafceer.mp3';

void playMukhtasarAudio(int s) =>
    AudioCtl.I.playUrl(mukhtasarAudioUrl(s), kMukhtasarAudioName, 'سورة ${surahName(s)}');

class MukhtasarAudioScreen extends StatelessWidget {
  const MukhtasarAudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final q = QuranData.I;
    return Scaffold(
      appBar: AppBar(title: const Text(kMukhtasarAudioName)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 14, 24, 8),
            child: Text(
              'التسجيل الصوتي للمختصر في تفسير القرآن الكريم\nإصدار مركز تفسير للدراسات القرآنية\nبصوت: عبدالله الأسمري\nوتلاوة: صابر عبدالحكم',
              textAlign: TextAlign.center,
              style: TextStyle(color: kGoldDeep, height: 1.8),
            ),
          ),
          GroupCard(children: [
            for (var s = 1; s <= 114; s++)
              ListTile(
                leading: const Icon(Icons.play_circle_outline_rounded, color: kEmerald),
                title: Text('${ar(s)}. ${surahName(s)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('الجزء ${ar(q.ayahs[q.surahStart[s]].juz)}', style: const TextStyle(fontSize: 12)),
                onTap: () {
                  playMukhtasarAudio(s);
                  toast(context, 'تشغيل تفسير سورة ${surahName(s)}');
                },
              ),
          ]),
        ],
      ),
    );
  }
}
