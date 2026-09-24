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
    final students = await db.collection('users').where('role', isEqualTo: 'student').get();
    if (!mounted) return;
    String query = '';
    String? selectedId;
    String? selectedName;
    String reason = 'Akademik takip';
    String day = 'Bugün';
    String time = '14:30';
    const reasons = ['Akademik takip','Ödev kontrolü','Sınav / hedef planlama','Ders çalışma düzeni','Motivasyon','Genel görüşme'];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final filtered = students.docs.where((d) {
          final x=d.data();
          final name='${x['fullName'] ?? '${x['name'] ?? ''} ${x['surname'] ?? ''}'}'.trim();
          final cls='${x['className'] ?? ''} ${x['branch'] ?? ''}'.trim();
          final q=query.toLowerCase();
          return q.isEmpty || name.toLowerCase().contains(q) || cls.toLowerCase().contains(q);
        }).toList();
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
            padding: const EdgeInsets.fromLTRB(18,18,18,14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF073D36),Color(0xFF07855F)]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(children:[
              Row(children:[
                Container(padding:const EdgeInsets.all(11),decoration:BoxDecoration(color:Colors.greenAccent.withValues(alpha:.16),shape:BoxShape.circle),child:const Icon(Icons.person_add_alt_1_rounded,color:Colors.greenAccent,size:28)),
                const SizedBox(width:12),
                const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Öğrenci Ekle',style:TextStyle(color:Colors.white,fontSize:23,fontWeight:FontWeight.w800)),Text('Kayıtlı öğrencilerden birini seçin.',style:TextStyle(color:Colors.white70,fontSize:12))])),
                IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close_rounded,color:Colors.white70)),
              ]),
              const SizedBox(height:14),
              TextField(onChanged:(v)=>setD(()=>query=v),style:const TextStyle(color:Colors.white),decoration:InputDecoration(hintText:'Öğrenci ara...',hintStyle:const TextStyle(color:Colors.white54),prefixIcon:const Icon(Icons.search_rounded,color:Colors.white70),filled:true,fillColor:Colors.white.withValues(alpha:.11),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide.none))),
              const SizedBox(height:12),
              Expanded(child:Container(decoration:BoxDecoration(color:Colors.white.withValues(alpha:.08),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white.withValues(alpha:.15))),child:ListView.separated(padding:const EdgeInsets.all(8),itemCount:filtered.length,separatorBuilder:(_,__)=>Divider(height:1,color:Colors.white.withValues(alpha:.10)),itemBuilder:(_,i){
                final d=filtered[i]; final x=d.data(); final name='${x['fullName'] ?? '${x['name'] ?? ''} ${x['surname'] ?? ''}'}'.trim(); final cls=['${x['className']??''}','${x['branch']??''}'].where((e)=>e.isNotEmpty).join(' • '); final selected=selectedId==d.id;
                return ListTile(onTap:()=>setD((){selectedId=d.id;selectedName=name;}),leading:CircleAvatar(backgroundColor:selected?Colors.greenAccent:Colors.white12,child:Icon(selected?Icons.check_rounded:Icons.person_rounded,color:selected?const Color(0xFF064A37):Colors.white)),title:Text(name,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700)),subtitle:cls.isEmpty?null:Text(cls,style:const TextStyle(color:Colors.white60)),trailing:selected?const Icon(Icons.check_circle_rounded,color:Colors.greenAccent):null);
              }))),
              if(selectedId!=null)...[
                const SizedBox(height:12),
                Row(children:[
                  Expanded(child:DropdownButtonFormField<String>(value:reason,dropdownColor:const Color(0xFF0A5948),style:const TextStyle(color:Colors.white),decoration:const InputDecoration(labelText:'Görüşme / görev',labelStyle:TextStyle(color:Colors.white70),enabledBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white38))),items:reasons.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setD(()=>reason=v??reason))),
                ]),
                const SizedBox(height:8),
                Row(children:[Expanded(child:TextFormField(initialValue:day,style:const TextStyle(color:Colors.white),decoration:const InputDecoration(labelText:'Gün',labelStyle:TextStyle(color:Colors.white70)),onChanged:(v)=>day=v)),const SizedBox(width:10),Expanded(child:TextFormField(initialValue:time,style:const TextStyle(color:Colors.white),decoration:const InputDecoration(labelText:'Saat',labelStyle:TextStyle(color:Colors.white70)),onChanged:(v)=>time=v))]),
              ],
              const SizedBox(height:12),
              SizedBox(width:double.infinity,height:50,child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:Colors.greenAccent,foregroundColor:const Color(0xFF064A37),disabledBackgroundColor:Colors.white12),onPressed:selectedId==null?null:()async{final u=await db.collection('users').doc(auth.currentUser!.uid).get();await db.collection('guidanceAppointments').add({'studentId':selectedId,'studentName':selectedName,'counselorId':auth.currentUser!.uid,'counselorName':u.data()?['fullName']??'Rehberlik Servisi','reason':reason,'dayLabel':day,'time':time,'status':'approved','source':'guidance','createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});if(ctx.mounted)Navigator.pop(ctx);},icon:const Icon(Icons.add_rounded),label:const Text('Görüşmeye Ekle',style:TextStyle(fontWeight:FontWeight.w800)))),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> addWeeklyTask() async {
    final students=await db.collection('users').where('role',isEqualTo:'student').get(); if(!mounted)return;
    String query=''; String? studentId,studentName; String title='Haftalık Ödev Kontrolü'; String day='Her Pazartesi';
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD){
      final filtered=students.docs.where((d){final x=d.data();final n='${x['fullName']??'${x['name']??''} ${x['surname']??''}'}'.toLowerCase();return query.isEmpty||n.contains(query.toLowerCase());}).toList();
      return Dialog(insetPadding:const EdgeInsets.symmetric(horizontal:18,vertical:24),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(28)),child:Container(constraints:const BoxConstraints(maxWidth:520,maxHeight:700),padding:const EdgeInsets.all(18),decoration:BoxDecoration(gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF092A50),Color(0xFF126B78)]),borderRadius:BorderRadius.circular(28)),child:Column(children:[
        Row(children:[const Icon(Icons.repeat_rounded,color:Colors.cyanAccent,size:30),const SizedBox(width:12),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Haftalık Takip Ver',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800)),Text('Öğrenci ve düzenli takip görevini seçin.',style:TextStyle(color:Colors.white70,fontSize:12))])),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close_rounded,color:Colors.white70))]),
        const SizedBox(height:12),TextField(onChanged:(v)=>setD(()=>query=v),style:const TextStyle(color:Colors.white),decoration:InputDecoration(hintText:'Öğrenci ara...',hintStyle:const TextStyle(color:Colors.white54),prefixIcon:const Icon(Icons.search_rounded,color:Colors.white70),filled:true,fillColor:Colors.white.withValues(alpha:.10),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide.none))),
        const SizedBox(height:10),Expanded(child:Container(decoration:BoxDecoration(color:Colors.white.withValues(alpha:.07),borderRadius:BorderRadius.circular(18)),child:ListView.builder(itemCount:filtered.length,itemBuilder:(_,i){final d=filtered[i],x=d.data();final n='${x['fullName']??'${x['name']??''} ${x['surname']??''}'}'.trim();final cls=['${x['className']??''}','${x['branch']??''}'].where((e)=>e.isNotEmpty).join(' • ');final sel=studentId==d.id;return ListTile(onTap:()=>setD((){studentId=d.id;studentName=n;}),leading:CircleAvatar(backgroundColor:sel?Colors.cyanAccent:Colors.white12,child:Icon(sel?Icons.check:Icons.person,color:sel?const Color(0xFF092A50):Colors.white)),title:Text(n,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700)),subtitle:cls.isEmpty?null:Text(cls,style:const TextStyle(color:Colors.white60)),trailing:sel?const Icon(Icons.check_circle,color:Colors.cyanAccent):null);}))),
        if(studentId!=null)...[const SizedBox(height:10),TextFormField(initialValue:title,style:const TextStyle(color:Colors.white),decoration:const InputDecoration(labelText:'Görev',labelStyle:TextStyle(color:Colors.white70)),onChanged:(v)=>title=v),const SizedBox(height:6),TextFormField(initialValue:day,style:const TextStyle(color:Colors.white),decoration:const InputDecoration(labelText:'Tekrar',labelStyle:TextStyle(color:Colors.white70)),onChanged:(v)=>day=v)],
        const SizedBox(height:12),SizedBox(width:double.infinity,height:50,child:FilledButton.icon(onPressed:studentId==null?null:()async{await db.collection('guidanceTasks').add({'studentId':studentId,'studentName':studentName,'counselorId':auth.currentUser!.uid,'title':title,'schedule':day,'active':true,'createdAt':FieldValue.serverTimestamp()});if(ctx.mounted)Navigator.pop(ctx);},icon:const Icon(Icons.repeat_rounded),label:const Text('Takibi Başlat')))
      ])));
    }));
  }

  @override Widget build(BuildContext context){final uid=auth.currentUser!.uid;return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:db.collection('users').doc(uid).snapshots(),builder:(context,userSnap){final name='${userSnap.data?.data()?['fullName']??'Rehberlik Servisi'}';return Scaffold(
    backgroundColor:const Color(0xFF071B36),appBar:AppBar(elevation:0,backgroundColor:const Color(0xFF0B2850),foregroundColor:Colors.white,title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(name,style:const TextStyle(fontWeight:FontWeight.w800)),const Text('Rehberlik Servisi',style:TextStyle(fontSize:11,color:Colors.white60))]),actions:[IconButton(onPressed:()=>auth.signOut(),icon:const Icon(Icons.logout_rounded))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:addStudent,icon:const Icon(Icons.person_add_alt_1_rounded),label:const Text('Öğrenci Ekle')),
    body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:db.collection('guidanceAppointments').where('counselorId',isEqualTo:uid).snapshots(),builder:(context,snap){if(!snap.hasData)return const Center(child:CircularProgressIndicator());final docs=snap.data!.docs.toList()..sort((a,b){final at=a.data()['createdAt'] as Timestamp?;final bt=b.data()['createdAt'] as Timestamp?;return(bt?.millisecondsSinceEpoch??0).compareTo(at?.millisecondsSinceEpoch??0);});final active=docs.where((d)=>!['completed','cancelled','no_show'].contains(d.data()['status'])).length;return ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF165D9C),Color(0xFF17A6A3)]),borderRadius:BorderRadius.circular(26)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Bugünün Rehberlik Akışı',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:5),Text('${docs.length} kayıt • $active aktif görüşme/talep',style:const TextStyle(color:Colors.white70)),const SizedBox(height:14),OutlinedButton.icon(style:OutlinedButton.styleFrom(foregroundColor:Colors.white,side:const BorderSide(color:Colors.white54)),onPressed:addWeeklyTask,icon:const Icon(Icons.repeat_rounded),label:const Text('Haftalık Takip Ver'))])),
      const SizedBox(height:16),if(docs.isEmpty)Container(padding:const EdgeInsets.all(28),decoration:BoxDecoration(color:Colors.white.withValues(alpha:.06),borderRadius:BorderRadius.circular(20)),child:const Center(child:Text('Henüz randevu veya görüşme yok.',style:TextStyle(color:Colors.white70)))),
      ...docs.map((doc){final x=doc.data();final s='${x['status']??'pending'}';final col=statusColor(s);return Container(margin:const EdgeInsets.only(bottom:12),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF102E55),Color(0xFF0D3B57)]),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white12)),child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[CircleAvatar(backgroundColor:col.withValues(alpha:.12),child:Icon(Icons.person_rounded,color:col)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${x['studentName']??'Öğrenci'}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800,fontSize:16)),Text('${x['dayLabel']??''} • ${x['time']??''} • ${x['reason']??''}',style:const TextStyle(color:Colors.white60,fontSize:12))])),Chip(label:Text(statusLabel(s)),backgroundColor:col.withValues(alpha:.10),labelStyle:TextStyle(color:col,fontWeight:FontWeight.w700))]),
        if(!['completed','cancelled','no_show'].contains(s))...[const Divider(height:22),Row(children:[if(s=='pending')Expanded(child:FilledButton(onPressed:()=>changeStatus(doc.id,'approved'),child:const Text('Onayla'))),if(s=='approved')Expanded(child:FilledButton(onPressed:()=>changeStatus(doc.id,'in_progress'),child:const Text('Görüşmeyi Başlat'))),if(s=='in_progress')Expanded(child:FilledButton(onPressed:()=>changeStatus(doc.id,'completed'),child:const Text('Görüşmeyi Tamamla'))),const SizedBox(width:8),OutlinedButton(onPressed:s=='in_progress'?null:()=>changeStatus(doc.id,'no_show'),child:const Text('Gelmedi'))])]
      ])));})
    ]);}),
  );});}
}