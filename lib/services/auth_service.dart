import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../db/app_database.dart';
import '../models/app_user.dart';
Future<String> _digest(List<String> input) async {
 final key=await Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:210000,bits:256).deriveKeyFromPassword(password:input[0],nonce:base64Decode(input[1]));
 return base64Encode(await key.extractBytes());
}
class AuthService {
 AuthService({AppDatabase? database}):_db=database??AppDatabase.instance;
 final AppDatabase _db;
 AppUser? _session;
 AppUser? get currentUser=>_session;
 void logout()=>_session=null;
 Future<bool> needsSetup() async => (await (await _db.db).query('user_credentials',limit:1)).isEmpty;
 Future<Map<String,Object?>> _credential(String user,String pin) async {
  if(!RegExp(r'^\d{6,12}$').hasMatch(pin))throw StateError('PIN 必须是 6–12 位数字');
  final random=Random.secure();final salt=base64Encode(List.generate(24,(_)=>random.nextInt(256)));
  return {'username':user.toLowerCase(),'salt':salt,'pin_hash':await compute(_digest,[pin,salt]),'failed_attempts':0,'locked_until':''};
 }
 Future<void> initializeAdmin(String pin) async {
  final record=await _credential('admin',pin);final db=await _db.db;
  await db.transaction((txn) async {
   if((await txn.query('user_credentials',limit:1)).isNotEmpty)throw StateError('管理员已初始化');
   await txn.insert('user_credentials',record);
  });
 }
 Future<AppUser> login(String username,String pin) async {
  final db=await _db.db;final name=username.trim().toLowerCase();
  final users=await db.query('demo_users',where:'lower(username)=? AND is_active=1',whereArgs:[name],limit:1);
  final creds=await db.query('user_credentials',where:'username=?',whereArgs:[name]);
  if(users.isEmpty||creds.isEmpty)throw StateError('账号或 PIN 无效，未设置 PIN 请联系管理员');
  final c=creds.first;final until=DateTime.tryParse(c['locked_until'] as String);
  if(until!=null&&until.isAfter(DateTime.now().toUtc()))throw StateError('尝试次数过多，请 5 分钟后重试');
  final actual=base64Decode(await compute(_digest,[pin,c['salt'] as String]));final expected=base64Decode(c['pin_hash'] as String);
  var diff=actual.length^expected.length;for(var i=0;i<actual.length&&i<expected.length;i++){diff|=actual[i]^expected[i];}
  if(diff!=0){
   await db.transaction((txn)async{
    await txn.rawUpdate('UPDATE user_credentials SET failed_attempts=failed_attempts+1 WHERE username=?',[name]);
    final row=(await txn.query('user_credentials',where:'username=?',whereArgs:[name])).single;
    if((row['failed_attempts'] as int)>=5)await txn.update('user_credentials',{'failed_attempts':0,'locked_until':DateTime.now().toUtc().add(const Duration(minutes:5)).toIso8601String()},where:'username=?',whereArgs:[name]);
   });
   throw StateError('账号或 PIN 无效');
  }
  await db.update('user_credentials',{'failed_attempts':0,'locked_until':''},where:'username=?',whereArgs:[name]);
  final u=users.first;return _session=AppUser(username:u['username'] as String,role:u['role']=='ADMIN'?AppRole.admin:AppRole.staff,displayName:u['display_name'] as String);
 }
 Future<void> setUserPin(String username,String pin) async {
  if(_session?.isAdmin!=true)throw StateError('仅管理员可设置 PIN');
  final db=await _db.db;
  if((await db.query('demo_users',where:'username=? COLLATE NOCASE',whereArgs:[username])).isEmpty)throw StateError('账号不存在');
  await db.insert('user_credentials',await _credential(username,pin),conflictAlgorithm:ConflictAlgorithm.replace);
 }
}
