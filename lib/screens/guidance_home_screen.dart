import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GuidanceHomeScreen extends StatelessWidget {
  const GuidanceHomeScreen({super.key});
  Future<void> changeStatus(BuildContext context,String id,String status) async {
    await FirebaseFirestore.instance.collection('guidanceAppointments').doc(id).update({'status':status,'updatedAt':FieldValue.serverTimestamp()});
    if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(status=='approved'?'Randevu onaylandı.':status=='in_progress'?'Görüşme başlatıldı.':status=='completed'?'Görüşme tamamlandı.':'Randevu güncellendi.')));
  }
  String label(String s)=>s=='approved'?'Onaylandı':s=='in_progress'?'Görüşmede':s=='completed'?'Tamamlandı':s=='no_show'?'Gelmedi':s=='cancelled'?'İptal':'Onay Bekliyor';
  Color color(String s)=>s=='completed'?Colors.greenAccent:s=='in_progress'?Colors.orangeAccent:s=='no_show'||s=='cancelled'?Colors.redAccent:s=='approved'?Colors.lightGreenAccent:Colors.cyanAccent;
  @override Widget build(BuildContext context){ final uid=FirebaseAuth.instance.currentUser!.uid; return Scaffold(
    backgroundColor:const Color(0xFF06142E),
    appBar:AppBar(backgroundColor:const Color(0xFF071A3A),foregroundColor:Colors.white,title:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Rehberlik',style:TextStyle(fontWeight:FontWeight.bold)),Text('Görüşme ve randevu yönetimi',style:TextStyle(fontSize:11,color:Colors.white60))]),actions:[IconButton(onPressed:()=>FirebaseAuth.instance.signOut(),icon:const Icon(Icons.logout_rounded))]),
    body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('guidanceAppointments').where('counselorId',isEqualTo:uid).snapshots(),builder:(context,snap){
      if(!snap.hasData)return const Center(child:CircularProgressIndicator());
      final docs=snap.data!.docs.toList()..sort((a,b){final at=a.data()['createdAt'] as Timestamp?;final bt=b.data()['createdAt'] as Timestamp?;return (bt?.millisecondsSinceEpoch??0).compareTo(at?.millisecondsSinceEpoch??0);});
      final active=docs.where((d)=>!['cancelled','completed','no_show'].contains(d.data()['status'])).length;
      return ListView(padding:const EdgeInsets.all(16),children:[
        Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF123A61),Color(0xFF17234F)]),borderRadius:BorderRadius.circular(24)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Randevularım',style:TextStyle(color:Colors.white,fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:7),Text('${docs.length} kayıt • $active aktif',style:const TextStyle(color:Colors.white70)),const SizedBox(height:8),const Text('Yeni öğrenci talebi bu ekrana anlık düşer.',style:TextStyle(color:Colors.cyanAccent,fontSize:12))])),
        const SizedBox(height:16),
        if(docs.isEmpty) Container(padding:const EdgeInsets.all(28),decoration:BoxDecoration(color:Colors.white.withValues(alpha:.05),borderRadius:BorderRadius.circular(20)),child:const Column(children:[Icon(Icons.event_busy_rounded,color:Colors.white38,size:38),SizedBox(height:10),Text('Henüz randevu talebi yok',style:TextStyle(color:Colors.white70))])),
        ...docs.map((doc){final x=doc.data();final s='${x['status']??'pending'}';final c=color(s);return Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.white.withValues(alpha:.06),borderRadius:BorderRadius.circular(19),border:Border.all(color:c.withValues(alpha:.28))),child:Column(children:[
          Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(width:58,padding:const EdgeInsets.symmetric(vertical:9),decoration:BoxDecoration(color:c.withValues(alpha:.12),borderRadius:BorderRadius.circular(13)),child:Text('${x['time']??''}',textAlign:TextAlign.center,style:TextStyle(color:c,fontWeight:FontWeight.bold))),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${x['studentName']??'Öğrenci'}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:15)),const SizedBox(height:3),Text('${x['dayLabel']??''} • ${x['reason']??''}',style:const TextStyle(color:Colors.white60,fontSize:12))])),Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:c.withValues(alpha:.12),borderRadius:BorderRadius.circular(20)),child:Text(label(s),style:TextStyle(color:c,fontSize:10,fontWeight:FontWeight.bold)))]),
          if(!['completed','cancelled','no_show'].contains(s))...[const SizedBox(height:11),Row(children:[if(s=='pending')Expanded(child:ElevatedButton(onPressed:()=>changeStatus(context,doc.id,'approved'),child:const Text('Onayla'))),if(s=='approved')Expanded(child:ElevatedButton(onPressed:()=>changeStatus(context,doc.id,'in_progress'),child:const Text('Görüşmeyi Başlat'))),if(s=='in_progress')Expanded(child:ElevatedButton(onPressed:()=>changeStatus(context,doc.id,'completed'),child:const Text('Tamamla'))),const SizedBox(width:7),TextButton(onPressed:()=>changeStatus(context,doc.id,'no_show'),child:const Text('Gelmedi'))])]
        ]));}).toList(),
      ]);
    }),
  );}
}