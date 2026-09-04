import 'package:cloud_firestore/cloud_firestore.dart';

class StoreModel {
  final String id, name, ownerId, category, city, description;
  final bool active, approved;
  final double rating;
  StoreModel({required this.id, required this.name, required this.ownerId, required this.category, required this.city, this.description = '', this.active = true, this.approved = true, this.rating = 0});
  factory StoreModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data() ?? {};
    return StoreModel(id: d.id, name: x['name'] ?? '', ownerId: x['ownerId'] ?? '', category: x['category'] ?? 'عام', city: x['city'] ?? 'عدن', description: x['description'] ?? '', active: x['active'] ?? true, approved: x['approved'] ?? false, rating: (x['rating'] ?? 0).toDouble());
  }
  Map<String, dynamic> toMap() => {'name': name, 'ownerId': ownerId, 'category': category, 'city': city, 'description': description, 'active': active, 'approved': approved, 'rating': rating};
}

class ProductModel {
  final String id, storeId, storeName, name, description, category, imageUrl;
  final double price;
  final int stock;
  final bool active;
  ProductModel({required this.id, required this.storeId, required this.storeName, required this.name, required this.price, required this.stock, this.description = '', this.category = 'عام', this.imageUrl = '', this.active = true});
  factory ProductModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) { final x=d.data()??{}; return ProductModel(id:d.id, storeId:x['storeId']??'', storeName:x['storeName']??'', name:x['name']??'', price:(x['price']??0).toDouble(), stock:(x['stock']??0) as int, description:x['description']??'', category:x['category']??'عام', imageUrl:x['imageUrl']??'', active:x['active']??true); }
  Map<String,dynamic> toMap()=>{'storeId':storeId,'storeName':storeName,'name':name,'price':price,'stock':stock,'description':description,'category':category,'imageUrl':imageUrl,'active':active};
}

class CartItem { final ProductModel product; int quantity; CartItem({required this.product,this.quantity=1}); double get total=>product.price*quantity; }

class OrderModel {
  final String id, userId, storeId, storeName, status, paymentMethod, address;
  final double total;
  final DateTime createdAt;
  final List<Map<String,dynamic>> items;
  OrderModel({required this.id,required this.userId,required this.storeId,required this.storeName,required this.status,required this.paymentMethod,required this.address,required this.total,required this.createdAt,required this.items});
  factory OrderModel.fromDoc(DocumentSnapshot<Map<String,dynamic>> d){final x=d.data()??{}; return OrderModel(id:d.id,userId:x['userId']??'',storeId:x['storeId']??'',storeName:x['storeName']??'',status:x['status']??'جديد',paymentMethod:x['paymentMethod']??'الدفع عند الاستلام',address:x['address']??'',total:(x['total']??0).toDouble(),createdAt:(x['createdAt'] as Timestamp?)?.toDate()??DateTime.now(),items:List<Map<String,dynamic>>.from(x['items']??[]));}
}
