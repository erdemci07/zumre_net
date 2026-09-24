import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GuidanceHomeScreen extends StatefulWidget {
  const GuidanceHomeScreen({super.key});
  @override State<GuidanceHomeScreen> createState()=>_GuidanceHomeScreenState();
}
class _GuidanceHomeScreenState extends State<GuidanceHomeScreen> {
  final db=FirebaseFirestore.instance; final auth=FirebaseAuth.instance;
  String statusLabel(String s)=>s=='approved'?'Onaylandı':s=='in_progress'?'Görüşmede':s=='completed'?'Tamamlandı':s=='no_show'?'Gelmedi':s=='cancelled'?'İptal':'Onay Bekliyor';
  Color statusColor(String s)=>s=='completed'?Colors.green:s=='in_progress'?Colors.orange:s=='no_show'||s=='cancelled'?Colors.red:s=='approved'?Colors.teal:const Color(0xFF2675D8);
  Future<void> changeStatus(String id,String status)=>db.collection('guidanceAppointments').doc(id).update({'status':status,'updatedAt':FieldValue.serverTimestamp()});

  Future<void> addStudent() async {
    final students=await db.collection('users').where('role',isEqualTo:'student').get();
    if(!mounted)return; String? studentId,studentName,reason; String day='Bugün'; String time='14:30';
    const reasons=['Akademik takip','Ödev kontrolü','Sınav / hedef planlama','Ders çalışma düzeni','Motivasyon','Genel görüşme'];
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Öğrenci Ekle'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(decoration:const InputDecoration(labelText:'Öğrenci'),items:students.docs.map((d){final x=d.data();final n='${x['fullName']??'${x['name']??''} ${x['surname']??''}'}';return DropdownMenuItem(value:d.id,child:Text(n));}).toList(),onChanged:(v){final d=students.docs.firstWhere((e)=>e.id==v).data();setD((){studentId=v;studentName='${d['fullName']??'${d['name']??''} ${d['surname']??''}'}';});}),
        const SizedBox(height:10),DropdownButtonFormField<String>(decoration:const InputDecoration(labelText:'Görüşme / görev'),items:reasons.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setD(()=>reason=v)),
        const SizedBox(height:10),TextFormField(initialValue:day,decoration:const InputDecoration(labelText:'Gün'),onChanged:(v)=>day=v),const SizedBox(height:10),TextFormField(initialValue:time,decoration:const InputDecoration(labelText:'Saat'),onChanged:(v)=>time=v),
      ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Vazgeç')),FilledButton(onPressed:studentId==null||reason==null?null:()async{final u=await db.collection('users').doc(auth.currentUser!.uid).get();await db.collection('guidanceAppointments').add({'studentId':studentId,'studentName':studentName,'counselorId':auth.currentUser!.uid,'counselorName':u.data()?['fullName']??'Rehberlik Servisi','reason':reason,'dayLabel':day,'time':time,'status':'approved','source':'guidance','createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});if(ctx.mounted)Navigator.pop(ctx);},child:const Text('Ekle'))]
    )));
  }

  Future<void> addWeeklyTask() async {
    final students=await db.collection('users').where('role',isEqualTo:'student').get(); if(!mounted)return;
    String? studentId,studentName; String title='Haftalık Ödev Kontrolü'; String day='Her Pazartesi';
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('Haftalık Takip Ver'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<String>(decoration:const InputDecoration(labelText:'Öğrenci'),items:students.docs.map((d){final x=d.data();final n='${x['fullName']??'${x['name']??''} ${x['surname']??''}'}';return DropdownMenuItem(value:d.id,child:Text(n));}).toList(),onChanged:(v){final d=students.docs.firstWhere((e)=>e.id==v).data();setD((){studentId=v;studentName='${d['fullName']??''}';});}),const SizedBox(height:10),
      TextFormField(initialValue:title,decoration:const InputDecoration(labelText:'Görev'),onChanged:(v)=>title=v),const SizedBox(height:10),TextFormField(initialValue:day,decoration:const InputDecoration(labelText:'Tekrar'),onChanged:(v)=>day=v)
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Vazgeç')),FilledButton(onPressed:studentId==null?null:()async{await db.collection('guidanceTasks').add({'studentId':studentId,'studentName':studentName,'counselorId':auth.currentUser!.uid,'title':title,'schedule':day,'active':true,'createdAt':FieldValue.serverTimestamp()});if(ctx.mounted)Navigator.pop(ctx);},child:const Text('Takibi Başlat'))])));
  }

  @override Widget build(BuildContext context){final uid=auth.currentUser!.uid;return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:db.collection('users').doc(uid).snapshots(),builder:(context,userSnap){final name='${userSnap.data?.data()?['fullName']??'Rehberlik Servisi'}';return Scaffold(
    backgroundColor:const Color(0xFFF4F7FB),appBar:AppBar(elevation:0,backgroundColor:Colors.white,foregroundColor:const Color(0xFF17375E),title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(name,style:const TextStyle(fontWeight:FontWeight.w800)),const Text('Rehberlik Servisi',style:TextStyle(fontSize:11,color:Colors.black54))]),actions:[IconButton(onPressed:()=>auth.signOut(),icon:const Icon(Icons.logout_rounded))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:addStudent,icon:const Icon(Icons.person_add_alt_1_rounded),label:const Text('Öğrenci Ekle')),
    body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:db.collection('guidanceAppointments').where('counselorId',isEqualTo:uid).snapshots(),builder:(context,snap){if(!snap.hasData)return const Center(child:CircularProgressIndicator());final docs=snap.data!.docs.toList()..sort((a,b){final at=a.data()['createdAt'] as Timestamp?;final bt=b.data()['createdAt'] as Timestamp?;return(bt?.millisecondsSinceEpoch??0).compareTo(at?.millisecondsSinceEpoch??0);});final active=docs.where((d)=>!['completed','cancelled','no_show'].contains(d.data()['status'])).length;return ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF165D9C),Color(0xFF17A6A3)]),borderRadius:BorderRadius.circular(26)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Bugünün Rehberlik Akışı',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:5),Text('${docs.length} kayıt • $active aktif görüşme/talep',style:const TextStyle(color:Colors.white70)),const SizedBox(height:14),OutlinedButton.icon(style:OutlinedButton.styleFrom(foregroundColor:Colors.white,side:const BorderSide(color:Colors.white54)),onPressed:addWeeklyTask,icon:const Icon(Icons.repeat_rounded),label:const Text('Haftalık Takip Ver'))])),
      const SizedBox(height:16),if(docs.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(28),child:Center(child:Text('Henüz randevu veya görüşme yok.')))),
      ...docs.map((doc){final x=doc.data();final s='${x['status']??'pending'}';final col=statusColor(s);return Card(margin:const EdgeInsets.only(bottom:12),elevation:1,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[CircleAvatar(backgroundColor:col.withValues(alpha:.12),child:Icon(Icons.person_rounded,color:col)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${x['studentName']??'Öğrenci'}',style:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),Text('${x['dayLabel']??''} • ${x['time']??''} • ${x['reason']??''}',style:const TextStyle(color:Colors.black54,fontSize:12))])),Chip(label:Text(statusLabel(s)),backgroundColor:col.withValues(alpha:.10),labelStyle:TextStyle(color:col,fontWeight:FontWeight.w700))]),
        if(!['completed','cancelled','no_show'].contains(s))...[const Divider(height:22),Row(children:[if(s=='pending')Expanded(child:FilledButton(onPressed:()=>changeStatus(doc.id,'approved'),child:const Text('Onayla'))),if(s=='approved')Expanded(child:FilledButton(onPressed:()=>changeStatus(doc.id,'in_progress'),child:const Text('Görüşmeyi Başlat'))),if(s=='in_progress')Expanded(child:FilledButton(onPressed:()=>changeStatus(doc.id,'completed'),child:const Text('Görüşmeyi Tamamla'))),const SizedBox(width:8),OutlinedButton(onPressed:s=='in_progress'?null:()=>changeStatus(doc.id,'no_show'),child:const Text('Gelmedi'))])]
      ])));})
    ]);}),
  );});}
}