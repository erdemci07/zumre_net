import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GuidanceHomeScreen extends StatefulWidget {
  const GuidanceHomeScreen({super.key});
  @override State<GuidanceHomeScreen> createState() => _GuidanceHomeScreenState();
}

class _GuidanceHomeScreenState extends State<GuidanceHomeScreen> {
  String day = 'Bugün';
  final items = <Map<String,String>>[
    {'time':'09:40','student':'Ece Yılmaz','info':'8 • DERSLİK 7 • Sınav / hedef planlama','status':'Tamamlandı'},
    {'time':'10:20','student':'Ahmet Demir','info':'7 • DERSLİK 6 • Akademik takip','status':'Görüşmede'},
    {'time':'11:10','student':'Zeynep Kaya','info':'10 • DERSLİK 6 • Motivasyon','status':'Bekliyor'},
    {'time':'13:40','student':'Ceren Aydın','info':'12 • DERSLİK 11 SAY • Ders çalışma düzeni','status':'Bekliyor'},
    {'time':'14:30','student':'Mert Şahin','info':'11 • DERSLİK 5 SAY • Genel görüşme','status':'Bekliyor'},
  ];
  Color statusColor(String s) => s=='Tamamlandı' ? Colors.greenAccent : s=='Görüşmede' ? Colors.orangeAccent : s=='Gelmedi' ? Colors.redAccent : Colors.cyanAccent;
  void setStatus(int i,String s){ setState(()=>items[i]['status']=s); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(items[i]['student']!+' • '+s))); }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06142E),
      appBar: AppBar(backgroundColor: const Color(0xFF071A3A), foregroundColor: Colors.white,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start,children:[Text('Rehberlik',style:TextStyle(fontWeight:FontWeight.bold)),Text('Görüşme ve randevu yönetimi',style:TextStyle(fontSize:11,color:Colors.white60))]),
        actions:[IconButton(onPressed:()=>FirebaseAuth.instance.signOut(),icon:const Icon(Icons.logout_rounded))]),
      body: SafeArea(child: ListView(padding:const EdgeInsets.all(16),children:[
        Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF123A61),Color(0xFF17234F)]),borderRadius:BorderRadius.circular(24),border:Border.all(color:Colors.white12)),
          child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Bugünün Görüşmeleri',style:TextStyle(color:Colors.white,fontSize:21,fontWeight:FontWeight.bold)),SizedBox(height:7),Text('5 görüşme • 1 aktif • 3 bekliyor',style:TextStyle(color:Colors.white70)),SizedBox(height:12),Row(children:[Icon(Icons.schedule_rounded,color:Colors.orangeAccent,size:18),SizedBox(width:7),Expanded(child:Text('Aktif görüşme planlanan süreden 8 dk ileride.',style:TextStyle(color:Colors.orangeAccent,fontSize:12.5)))])])),
        const SizedBox(height:14),
        Row(children:['Bugün','Yarın','Haftalık'].map((d)=>Expanded(child:Padding(padding:const EdgeInsets.only(right:7),child:ChoiceChip(label:Center(child:Text(d)),selected:day==d,onSelected:(_)=>setState(()=>day=d))))).toList()),
        const SizedBox(height:16),
        Row(children:[const Expanded(child:Text('Randevu Akışı',style:TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.bold))),TextButton.icon(onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Öğrenci ekleme ekranı açıldı.'))),icon:const Icon(Icons.person_add_alt_1_rounded),label:const Text('Öğrenci Ekle'))]),
        const SizedBox(height:6),
        ...List.generate(items.length,(i){ final x=items[i]; final status=x['status']!; final color=statusColor(status); return Container(
          margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.white.withValues(alpha:.06),borderRadius:BorderRadius.circular(19),border:Border.all(color:color.withValues(alpha:.28))),
          child:Column(children:[Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Container(width:58,padding:const EdgeInsets.symmetric(vertical:9),decoration:BoxDecoration(color:color.withValues(alpha:.12),borderRadius:BorderRadius.circular(13)),child:Text(x['time']!,textAlign:TextAlign.center,style:TextStyle(color:color,fontWeight:FontWeight.bold))),
            const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(x['student']!,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:15)),const SizedBox(height:3),Text(x['info']!,style:const TextStyle(color:Colors.white60,fontSize:12))])),
            Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:color.withValues(alpha:.12),borderRadius:BorderRadius.circular(20)),child:Text(status,style:TextStyle(color:color,fontSize:11,fontWeight:FontWeight.bold)))
          ]),
          if(status!='Tamamlandı'&&status!='Gelmedi')...[const SizedBox(height:11),Row(children:[
            if(status=='Bekliyor') Expanded(child:OutlinedButton(onPressed:()=>setStatus(i,'Görüşmede'),child:const Text('Görüşmeyi Başlat'))),
            if(status=='Görüşmede') Expanded(child:ElevatedButton(onPressed:()=>setStatus(i,'Tamamlandı'),child:const Text('Görüşmeyi Tamamla'))),
            const SizedBox(width:8),TextButton(onPressed:()=>setStatus(i,'Gelmedi'),child:const Text('Gelmedi'))
          ])]])); }),
        const SizedBox(height:8),
        Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.cyanAccent.withValues(alpha:.07),borderRadius:BorderRadius.circular(18),border:Border.all(color:Colors.cyanAccent.withValues(alpha:.20))),child:const Row(children:[Icon(Icons.notifications_active_outlined,color:Colors.cyanAccent),SizedBox(width:10),Expanded(child:Text('Sıradaki öğrenciye görüşme yaklaşınca bildirim gönderilir; saat değişirse yeni saat öğrenciye yansıtılır.',style:TextStyle(color:Colors.white70,fontSize:12.5)))])),
      ])),
    );
  }
}